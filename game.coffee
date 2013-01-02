
MIN_MASS_KG = 0.0001
MIN_DAMPING = 0.001
MAX_DAMPING = 9999999
IMPULSE_FORCE_SCALE = 120
PLAYER_DAMPING = 12
PLAYER_MASS_KG = 100
body = document.body
aspect_ratio = 16 / 9
h = Math.max(body.scrollHeight, body.clientHeight)
w = h / aspect_ratio
PLAYER_RADIUS = w/48
BALL_RADIUS = w/90

# w and h are the real-pixel heights of the canvas
# we also need a conversion from pixels to yards and back
# for now, we just assume that the play area is 40yds long
yard = yards = h/40
# so, (10*yards) is the number of pixels in 10 yards
# and (10/yards) is the number of yards in 10 pixels


# Create the canvas to draw on
canvas = $("canvas")
	.zap("height", h)
	.zap("width", w)
	.css # center the canvas
		position: "fixed"
		left: "50%"
		padding: "0"
		margin: "0 0 0 #{$.px -w/2}"

# Create the drawing context
context = canvas.select('getContext').call('2d')

# Draw a placeholder splash sequence
context.each ->
	fillMultiLineText = (interval, lines...) =>
		for i in [0...lines.length] by 1
			@fillText lines[i], w/2, interval * (i+1)

	textIndex = 0
	texts = [
		" READY TO PLAY?".split(' ')
		" CLICK TO START!".split(' ')
	]
	drawText = =>
		@fillStyle = 'black'
		@fillRect 0,0,w,h
		@fillStyle = 'white'
		@textAlign = 'center'
		@font = "#{$.px w/4} courier"
		fillMultiLineText h/5, texts[textIndex++]...
		if textIndex < texts.length
			setTimeout drawBolt, 1000

	drawBolt = =>
		@beginPath()
		@moveTo w*.6, 0
		@lineTo w*.4, h*.6
		@lineTo w*.5, h*.66
		@lineTo w*.3, h
		@lineTo w*.6, h*.66
		@lineTo w*.5, h*.6
		@lineTo w*.7, 0
		@closePath()
		@fillStyle = 'white'
		@fill()
		setTimeout drawText, 100
	
	drawFlash = =>
		@fillStyle = 'white'
		@fillRect 0,0,w,h
		setTimeout drawText, 100
	
	drawText()
	

# Entity is the base class for all world objects; it handles physics, etc.
class Entity extends $.EventEmitter
	distance_cache = Object.create null # used to help collision detection
	@clearCaches = ->
		distance_cache = Object.create null
	@removeFromCache = (ent) ->
		delete distance_cache[ent.guid]
		for k of distance_cache
			delete distance_cache[k][ent.guid]

	# property functions:
	fill: (@_fill) -> @
	stroke: (@_stroke) -> @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	damping: (c) -> @_damping = Math.min(MAX_DAMPING, Math.max(MIN_DAMPING, c)); @
	position: (x...) -> @x = $ x; @

	constructor: ->
		@guid = $.random.string 8
		@x = $.zeros(2) # position in m (actually, in px, a problem, since it should be in m)
		@kg = MIN_MASS_KG # mass in kg
		@_damping = MIN_DAMPING # damping coefficient (unitless)
		@fullStop()
	
	# come to a complete and instant stop
	fullStop: ->
		@a = $.zeros(2) # acceleration in m/s^2
		@v = $.zeros(2) # velocity in m/s
		@forces = Object.create null # the set of (temporary) forces on this object

	# get the distance between objects, using caching
	# suitable for use in [collision] loops in a single frame
	getDistance: (entB) ->
		a = @guid
		b = entB.guid
		if a of distance_cache and b of distance_cache[a]
			return distance_cache[a][b]
		if b of distance_cache and a of distance_cache[b]
			return distance_cache[b][a]
		distance_cache[a] or= Object.create null
		distance_cache[b] or= Object.create null
		distance_cache[a][b] = distance_cache[b][a] = @x.minus(entB.x).magnitude()
	
	# applies a temporary force to this entity
	applyForce: (duration, x...) ->
		$.log "applying force: #{x} for duration: #{duration}"
		expires = $.now + duration
		(@forces[expires] or= []).push x

	# applies a force function to this entity
	# the force function receives the entity to be forced, and returns a force vector
	applyDynamicForce: (duration, f) ->
		expires = $.now + duration
		(@forces[expires] or= []).push f

	# adjust our position by this offset (with sanity checks)
	translate: (dx...) ->
		for i in [0...dx.length] by 1
			if (not isFinite dx[i]) # or (Math.abs dx[i]) < .0001
				dx[i] = 0
		if dx[0] isnt 0 or dx[1] isnt 0
			@x = @x.plus dx
			Entity.removeFromCache @
		@

	# run one frame for just this object
	tick: (dt) ->
		dts = dt/1000 # convert time to seconds; so physics works in m/s
		now = $.now

		# Add up all the forces on this object
		total_force = $.zeros(2)

		# Temporary forces are organized by expiration time
		for expires,forces of @forces
			# if they are expired, just clean them out
			if now >= expires
				delete @forces[expires]
				continue
			# otherwise, add up all the forces in this time bucket
			for force in forces
				total_force = total_force.plus switch $.type force
					when 'bling','array' then force
					when 'function' then force(@)
					else ($.log 'invalid force', force; [0,0])

		# always include the damping force
		total_force = total_force.plus @v.scale(-@_damping)

		# use collision to:
		#  * initiate grappling
		#  * pick up loose balls
		if $.isType FootballPlayer, @
			# add forces from people grappling onto us
			if @grapple.by?
				@fullStop()
				@attemptBreakGrapple()
			else if not @hasBall
				for obj in objects
					if $.isType Football, obj
						continue if obj.owner?
						d = @getDistance(obj)
						r = @r + obj.r
						if d < r
							@giveBall(obj)
					if $.isType FootballPlayer, obj
						continue if obj.guid is @guid
						continue if obj._team is @_team
						d = @getDistance(obj)
						r = @r + obj.r
						if d < r
							@attemptGrapple(obj)
							total_force = $.zeros(2)

		# Apply accel->velocity->position using vertlet integration:
		# 1. adjust the position based on current velocity plus some part of the acceleration
		@translate @v.scale(dts).plus(@a.scale(.5 * dts * dts))...
		# 2. compute the new acceleration from total force
		new_acceleration = total_force.scale(1/@kg)
		# 3. adjust velocity based on two-frame average acceleration
		@v = @v.plus(new_acceleration.plus(@a).scale(.5))
		# 4. record acceleration for averaging
		@a = new_acceleration

	preDraw: (ctx) ->
		ctx.translate @x...
		if @facing then ctx.rotate @facing
		if @_fill then ctx.fillStyle = @_fill
		if @_stroke then ctx.strokeStyle = @_stroke
	draw: (ctx) ->
		if @_fill then ctx.fill()
		if @_stroke then ctx.stroke()

class Rect extends Entity
	constructor: ->
		super @
		@w = @h = 0
	size: (@w, @h) -> @
	area: -> @w * @h
	draw: (ctx) ->
		ctx.beginPath()
		ctx.rect 0,0,@w,@h
		ctx.closePath()
		super ctx

class FootballField extends Rect
	constructor: ->
		super @
		@fill('green')
			.damping(MAX_DAMPING)

class Text extends Entity
	text: (@_text) -> @
	font: (@_font) -> @
	textAlign: (@_textAlign) -> @
	draw: (ctx) ->
		if @_font then ctx.font = @_font
		if @_textAlign then ctx.textAlign = @_textAlign
		if @_fill then ctx.fillText @_text, @x...
		if @_stroke then ctx.strokeText @_stroke, @x...
		super ctx

class window.Circle extends Entity
	instances = $()
	@get = (i) -> instances[i]
	@findAt = (x...) ->
		instances.filter((-> @x.minus(x).magnitude() < @r), 1).first()
	constructor: ->
		super @
		instances.push @
		@r = 0
	radius: (@r) -> @
	area: -> Math.PI * @r * @r
	draw: (ctx) ->
		ctx.beginPath()
		ctx.arc 0, 0, @r, 0, Math.PI*2, true
		ctx.closePath()
		super ctx

Teams =
	red: -> @fill('red')
	blue: -> @fill('blue')

class window.Football extends Circle
	constructor: ->
		super @
		@owner = null
		@highlighted = false
		@radius(BALL_RADIUS)
			.damping(PLAYER_DAMPING)
			.mass(PLAYER_MASS_KG)
	tick: (dt) ->
		if @owner?
			x = @owner.x
			if @x.minus(x).magnitude() > 2
				r = @r*1.5
				@position x.plus([r,r])...
		else
			super dt
	draw: (ctx) ->
		ctx.beginPath()
		end = -Math.PI
		if @owner?
			end = -Math.PI/2
		ctx.arc 0,0, @r, Math.PI, end, true
		ctx.lineWidth = @r*2
		ctx.strokeStyle = 'brown'
		ctx.stroke()
		ctx.closePath()

		ctx.beginPath()
		y = -@r*.5
		ctx.moveTo @r, y
		ctx.lineTo y, @r
		ctx.lineWidth = w >>> 8
		ctx.strokeStyle = 'white'
		ctx.stroke()
		ctx.closePath()

		if @highlighted
			ctx.beginPath()
			ctx.arc 0,0,@r, Math.PI, end, true
			ctx.strokeStyle = 'yellow'
			unless @owner?
				ctx.strokeStyle = 'red'
			ctx.lineWidth = w >>> 8
			ctx.stroke()
			ctx.closePath()

	
class window.FootballPlayer extends Circle
	team: (@_team) -> Teams[@_team]?.call @; @
	constructor: (team) ->
		super @
		@highlighted = false
		@grapple =
			by: null
			ing: null
		@number = $.random.integer 1,99
		@damping(PLAYER_DAMPING)
			.mass(PLAYER_MASS_KG)
			.radius(PLAYER_RADIUS)
			.team(team)
	toggleHighlight: ->
		@highlight = not @highlighted
	attemptGrapple: (other) ->
		# $.log @guid, 'grappling', other.guid
		@grapple.ing = other
		other.grapple.by = @
	attemptBreakGrapple: ->
		dx = @x.minus(@grapple.by.x)
		gap = dx.magnitude() - (@r + @grapple.by.r)
		@grapple.by.grapple.ing = null
		@grapple.by = null
		if gap < 0
			delta = dx.normalize().scale(-gap).scale(1.05) #.scale($.random.real(.6,1.4))
			@translate delta...
	giveBall: (ball) ->
		return if ball.prevOwner is @
		(ball.owner = @).ball = ball
	releaseBall: ->
		if @ball?
			b = @ball
			b.prevOwner = @
			@ball = b.owner = null
			$.delay 300, -> b.prevOwner = null
	
	drawHighlight: (ctx) ->
		ctx.beginPath()
		ctx.arc 0, 0, @r, 0, Math.PI*2, true
		ctx.lineWidth = w/256
		ctx.strokeStyle = 'yellow'
		ctx.stroke()
		ctx.closePath()

	drawNumbers: (ctx) ->
		ctx.textAlign = 'center'
		ctx.fillStyle = 'white'
		ctx.font = "#{$.px .66*yards} courier"
		ctx.fillText @number, 0,@r/2
	
	drawBall: (ctx) ->
		ctx.beginPath()
		ctx.arc 0,0, @r, 0, Math.PI*2, true
		ctx.strokeStyle = 'brown'
		ctx.lineWidth = w/256
		ctx.stroke()
		ctx.closePath()

	draw: (ctx) ->
		super ctx
		if @ball? then @drawBall ctx
		if @highlighted then @drawHighlight ctx
		@drawNumbers ctx

objects = []
window.clock = new Clock()
clock.on 'tick', (dt) ->
	# Entity.clearCaches()
	for obj in objects
		obj.tick(dt)
	for obj in objects
		context.each ->
			@save()
			obj.preDraw @
			obj.draw @
			@restore()
clock.on 'started', -> $.log 'started'
clock.on 'stopped', -> $.log 'stopped'
objects.push new FootballField().position(0,0).size(w,h)
gameBall = new Football().position(w/2,h/2)

Formations =
	defense:
		"4-3":
			positions: [
				[-5, -10], [5, -10], # FS + SS
				[-9, -2.5], [9, -2.5], # CB x 2
				[-4, -4.5], [0, -4.5], [4, -4.5], # LB x 3
				[-3, -1.5], [-1, -1.5], [1, -1.5], [3, -1.5], # DL x 4
			]
	offense:
		"single-back":
			positions: [
				[-3,0.5], [-1.5,0.5], # LG,LT
				[0,0.5], # C
				[3,0.5],[1.5,0.5], # RG,RT
				[0,1.5], # QB
				[0,4.5], # HB
				[-8,1.5], [8,1.5], # WR
			]
			ball: 5
spawnFormation = (x,y,formation, team) ->
	start = objects.length
	for pos in formation.positions
		objects.push new FootballPlayer(team).position(pos[0]*yards+x,pos[1]*yards+y)
	if formation.ball
		objects[start + formation.ball].giveBall(gameBall)

objects.push gameBall
spawnFormation(w/2,h/1.5, Formations.defense["4-3"], 'red')
spawnFormation(w/2,h/1.5, Formations.offense["single-back"], 'blue')

Event.position = (evt) ->
	$ evt.offsetX, evt.offsetY

MouseEvent::position = -> $ @offsetX, @offsetY
TouchEvent::position = -> $ @touches[0].clientX, @touches[0].clientY

class ImpulseVector extends Entity
	constructor: ->
		super @
		@reset()
		canvas.bind 'mousedown', (evt) =>
			clock.start()
			$.log '@dragTarget', @dragTarget = Circle.findAt(evt.position()...)
			if @dragTarget
				@dragStart = @dragTarget.x
				@dragEnd = @dragStart.slice()
				@dragTarget.highlighted = true
			evt.preventAll()
		canvas.bind 'touchcancel', (evt) =>
			@dragTarget?.highlighted = false
			@reset()
		canvas.bind 'mouseup, mouseout', (evt) => @applyForce(); evt.preventAll()
		canvas.bind 'mousemove', (evt) =>
			@dragEnd = evt.position()
	reset: ->
		@dragTarget = @dragStart = @dragEnd = null
	applyForce: ->
		if @dragTarget
			delta = @dragStart.minus(@dragEnd).scale(IMPULSE_FORCE_SCALE)
			if delta.magnitude() > 0
				ok = true
				if $.isType Football, @dragTarget
					# a football with no owner cannot be moved
					unless @dragTarget.owner?
						ok and= false
					# and impulsing the ball is akin to throwing it, it is removed from its owner
					@dragTarget.owner?.releaseBall()
				if ok
					@dragTarget.applyForce 100, delta...
				@dragTarget.highlighted = false
			else clock.stop()
		@reset()

	draw: (ctx) ->
		if @dragTarget and @dragEnd
			target = @dragTarget.x
			ctx.translate 0,0
			ctx.beginPath()
			ctx.moveTo target...
			ctx.lineTo target.minus(@dragEnd).plus(target)...
			ctx.lineWidth = w/128
			ctx.strokeStyle = 'white'
			if $.isType Football, @dragTarget
				if @dragTarget.owner?
					ctx.strokeStyle = 'yellow'
				else
					ctx.strokeStyle = 'red'
			ctx.stroke()
			ctx.closePath()

objects.push new ImpulseVector()
