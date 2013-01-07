
MIN_MASS_KG = 0.0001
MIN_DAMPING = 0.001
MAX_DAMPING = 99999999999999
IMPULSE_FORCE_SCALE = 120
PLAYER_DAMPING = 12
PLAYER_MASS_KG = 100
body = document.body
h = Math.max(body.scrollHeight, body.clientHeight)
w = h * 9 / 16
# w and h are the real-pixel heights of the canvas
# we also need a conversion from pixels to yards and back
# for now, we just assume that the play area is 40yds long
yard = yards = h/40
# so, (10*yards) is the number of pixels in 10 yards
# and (10/yards) is the number of yards in 10 pixels
PLAYER_RADIUS = .5*yard
BALL_RADIUS = .5*yard
MOVES_PER_TURN = 2
turnCounter = MOVES_PER_TURN
lineOfScrimmage = 20
lineOfScrimmageX = w/2
lineOfScrimmageY = h/1.5
firstDownMarker = 30
firstDownY = lineOfScrimmageY + (firstDownMarker - lineOfScrimmage * yards)
$.log = $.throttle 50, $.log
$.log 'configured'

# This is the set of game objects (things that will tick and render in every frame)
window.objects = []
# This clock drives the game loop, emitting a 'tick' event at 60fps.
window.clock = new Clock()
clock.on 'tick', (dt) -> # This is the cental game loop
	# First, we call .tick() on every object so it can update state (position, etc)
	for obj in objects
		obj.tick(dt)
	# Second, we draw every item in every context.
	for obj in objects
		context.each ->
			@save()
			obj.preDraw @
			obj.draw @
			@restore()
clock.on 'started', -> $.log 'started'
clock.on 'stopped', -> $.log 'stopped'

$.log 'clock created'

# Get the canvas to draw on
canvas = $("canvas") # TODO: currently hardcoded here to take over all canvases on a page
	.zap("height", h)
	.zap("width", w)
	.css # center the canvas
		position: "fixed"
		left: "50%"
		padding: "0"
		margin: "0 0 0 #{$.px -w/2}"

$.log 'canvas found'

# Create the drawing context
context = canvas.select('getContext').call('2d')

$.log 'context created'

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
		# if textIndex < texts.length then setTimeout drawBolt, 1000

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
		return unless ('guid' of ent and ent.guid of distance_cache)
		for k,v of distance_cache[ent.guid]
			delete v[ent.guid]
		delete distance_cache[ent.guid]

	# property functions:
	fill: (f) -> @style.fill = f; @
	stroke: (s) -> @style.stroke = s; @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	damping: (c) ->
		@pos.damping = Math.min MAX_DAMPING, Math.max MIN_DAMPING, c
		@
	rotdamping: (c) ->
		@rot.damping = Math.min MAX_DAMPING, Math.max MIN_DAMPING, c
		@
	position: (x...) -> @pos.x = $ x; @

	constructor: ->
		@guid = $.random.string 8
		@style =
			fill: null
			stroke: null
		@size = # describes a bounding box/circle
			w: 0 # width
			h: 0 # height
			r: 0 # radius
		@pos =
			x: $.zeros(2) # position in m (actually, in px, a problem, since it should be in m)
		@kg = MIN_MASS_KG # mass in kg
		@fullStop()

	# come to a complete and instant stop
	fullStop: ->
		@rot =
			x: 0
			v: 0
			a: 0
			damping: MIN_DAMPING
		@pos =
			x: @pos.x
			v: $.zeros(@pos.x.length)
			a: $.zeros(@pos.x.length)
			damping: MIN_DAMPING
		@forces = Object.create null # the set of (temporary) forces on this object
		@torques = Object.create null

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
		distance_cache[a][b] = distance_cache[b][a] = @pos.x.minus(entB.pos.x).magnitude()

	# applies a temporary force to this entity
	applyForce: (duration, x...) ->
		if x.length is 1 and $.type(x[0]) in ['array','bling']
			x = x[0]
		(@forces[$.now + duration] or= []).push x

	# applies a force function to this entity
	# the force function receives the entity to be forced, and returns a force vector
	applyDynamicForce: (duration, f) ->
		(@forces[$.now + duration] or= []).push f

	applyTorque: (duration, t) ->
		$.log 'applying torque', t, 'for', duration
		(@torques[$.now + duration] or= []).push t

	# adjust our position by this offset (with sanity checks)
	translate: (dx...) ->
		for i in [0...dx.length] by 1
			if (not isFinite dx[i]) # or (Math.abs dx[i]) < .0001
				dx[i] = 0
		if dx[0] isnt 0 or dx[1] isnt 0
			@pos.x = @pos.x.plus dx
			Entity.removeFromCache @
		@

	rotation: (angle) ->
		return unless isFinite(angle)
		@rot.x = angle; @
	rotate: (angle) ->
		return unless isFinite(angle)
		@rot.x += angle; @

	getTotalForce: ->
		total_force = $.zeros(2)
		now = $.now
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
		total_force = total_force.plus @pos.v.scale(-@pos.damping)

	getTotalTorque: ->
		total_torque = 0
		now = $.now
		for expires, torques of @torques
			$.log "checking torque #{expires} #{torques}"
			if now >= expires
				$.log 'expiring torque'
				delete @torques[expires]
				continue
			for torque in torques
				$.log 'adding torque', torque
				total_torque += switch $.type torque
					when 'number' then torque
					when 'function' then torque(@)
					else ($.log 'invalid torque', torque; 0)
		if not isFinite(@rot.v)
			$.log "V rotted"
			@rot.v = 0
		if not isFinite(@rot.damping)
			$.log "DAMPING rotted"
			@rot.damping = MIN_DAMPING
		damping = @rot.v * -@rot.damping
		if damping isnt 0
			$.log 'torque decay', damping
		total_torque += @rot.v * -@rot.damping * @rot.damping
	
	doCollision: (total_force) ->
		# use collision to:
		#  * initiate grappling
		#  * pick up loose balls
		if $.isType FootballPlayer, @
			# add forces from people grappling onto us
			if @grapple.by?
				@fullStop()
				@attemptBreakGrapple()
			# TODO: keep tugging 
			# else if @grapple.ing?
			else if not @hasBall
				for obj in objects
					# check the football
					if $.isType Football, obj
						unless obj.owner? # if the ball is not owned
							if @overlaps(obj) # and we are touching it
								@giveBall(obj) # take it
					# check other players
					if $.isType FootballPlayer, obj
						# skip ourselves
						continue if obj.guid is @guid
						# skip (for now) people on our own team
						continue if obj.jersey.team is @jersey.team
						# if we are touching this other player
						if @overlaps(obj)
							# grapple them
							@attemptGrapple(obj)
							total_force = $.zeros(2)
		return total_force
	
	adjustPosition: (total_force, dt) ->
		# Adjust position (x,a,v) using vertlet integration:
		# 1. adjust the position based on current velocity plus some of the acceleration
		@translate @pos.v.scale(dt).plus(@pos.a.scale(.5 * dt * dt))...
		# 2. compute the new acceleration from total force
		new_acceleration = total_force.scale(1/@kg)
		# 3. adjust velocity based on two-frame average acceleration
		@pos.v = @pos.v.plus(new_acceleration.plus(@pos.a).scale(.5))
		# 4. record acceleration for averaging
		@pos.a = new_acceleration

	adjustRotation: (total_torque, dt) ->
		# Adjust our rotation angle the same basic way
		@rotate (@rot.v * dt) + (@rot.a * .5 * dt * dt)
		new_acceleration = total_torque * 1 / @kg
		# if new_acceleration isnt 0 then $.log 'new_acceleration', new_acceleration
		@rot.v += (new_acceleration + @rot.a) / 2
		@rot.a = new_acceleration

	# run one frame for just this object
	tick: (dt) ->
		dts = dt/1000 # convert time to seconds; so physics works in m/s

		# Add up all the forces on this object
		total_force = @getTotalForce()
		total_torque = @getTotalTorque()
		# if total_torque isnt 0 then $.log 'total_torque', total_torque

		total_force = @doCollision(total_force)

		@adjustPosition total_force, dts
		@adjustRotation total_torque, dts


	preDraw: (ctx) ->
		ctx.translate @pos.x...
		if @rot.x then ctx.rotate @rot.x
		if @style.fill then ctx.fillStyle = @style.fill
		if @style.stroke then ctx.strokeStyle = @style.stroke
	draw: (ctx) ->
		if @style.fill then ctx.fill()
		if @style.stroke then ctx.stroke()

class Rect extends Entity
	constructor: ->
		super @
	bounds: (w,h) -> @size = { w, h, r: Math.max(w,h)/2 }; @
	area: -> @size.w * @size.h
	draw: (ctx) ->
		ctx.beginPath()
		ctx.rect 0,0,@size.w, @size.h
		ctx.closePath()
		super ctx

class FootballField extends Rect
	constructor: ->
		super @
		@fill('green')
			.damping(MAX_DAMPING)
	draw: (ctx) ->
		super ctx
		ctx.beginPath()
		fiveYards = 5 * yards
		hundredYards = 100 * yards
		i = 0
		for y in [0...hundredYards] by yard
			i += 1
			if i % 5 == 0
				ctx.moveTo 0, y
				ctx.lineTo w, y
			else
				ctx.moveTo w*.4,y
				ctx.lineTo w*.44,y
				ctx.moveTo w*.6,y
				ctx.lineTo w*.64,y
		ctx.strokeStyle = 'white'
		ctx.stroke()
		ctx.closePath()


class Text extends Entity
	text: (t) -> @style.text = t; @
	font: (f) -> @style.font = f; @
	textAlign: (a) -> @style.textAlign = a; @
	draw: (ctx) ->
		if @style.font then ctx.font = @style.font
		if @style.textAlign then ctx.textAlign = @style.textAlign
		if @style.fill then ctx.fillText @style.text, @pos.x...
		if @style.stroke then ctx.strokeText @style.stroke, @pos.x...
		super ctx

class window.Circle extends Entity
	instances = $()
	@get = (i) -> instances[i]
	@findAt = (x...) ->
		instances.filter((-> @pos.x.minus(x).magnitude() < @size.r), 1).first()
	constructor: ->
		super @
		instances.push @
		@size.r = 0
	radius: (r) -> @size.r = r; @
	area: -> Math.PI * @size.r * @size.r
	overlaps: (circleB) ->
		d = @getDistance circleB
		return d < (@size.r + circleB.r)
	draw: (ctx) ->
		ctx.beginPath()
		ctx.arc 0, 0, @size.r, 0, Math.PI*2, true
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
			.rotdamping(MAX_DAMPING)
			.mass(PLAYER_MASS_KG)
	tick: (dt) ->
		if @owner?
			x = @owner.pos.x
			rx = @owner.rot.x
			if @pos.x.minus(x).magnitude() > 2
				r = @size.r*.9
				@position x.plus([r,r])...
			if @rot.x - rx > 0
				@rotation rx
		else
			super dt
	draw: (ctx) ->
		r = @size.r
		ctx.beginPath()
		ctx.arc 0,0, r, 0, Math.PI*2, true
		ctx.fillStyle = 'brown'
		ctx.fill()
		ctx.closePath()

		ctx.beginPath()
		y = -r*.25
		ctx.moveTo r/2, y
		ctx.lineTo y, r/2
		ctx.lineWidth = w >>> 8
		ctx.strokeStyle = 'white'
		ctx.stroke()
		ctx.closePath()

		if @highlighted
			ctx.beginPath()
			ctx.arc 0,0,r, 0, Math.PI*2, true
			ctx.strokeStyle = 'yellow'
			unless @owner?
				ctx.strokeStyle = 'red'
			ctx.lineWidth = w >>> 8
			ctx.stroke()
			ctx.closePath()


class window.FootballPlayer extends Circle
	team: (t) ->
		@jersey.team = t
		Teams[t]?.call @
		@
	constructor: (team) ->
		super @
		@jersey =
			number: $.padLeft($.random.integer(1,99).toString(), 2, "0")
			name: "John Smith"
			team: null
		@highlighted = false
		@grapple =
			by: null # who am I grappled by
			ing: null # who am I grappling
		@damping(PLAYER_DAMPING)
			.mass(PLAYER_MASS_KG)
			.radius(PLAYER_RADIUS)
			.team(team)
	toggleHighlight: ->
		@highlight = not @highlighted
	attemptGrapple: (other) ->
		@grapple.ing = other
		other.grapple.by = @
	attemptBreakGrapple: ->
		dx = @pos.x.minus(@grapple.by.pos.x)
		gap = dx.magnitude() - (@size.r + @grapple.by.size.r)
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
			$.delay 500, =>
				if b.prevOwner is @ # unless it changed since we were scheduled
					b.prevOwner = null # clear off our previous ownership

	drawHighlight: (ctx) ->
		ctx.beginPath()
		ctx.arc 0, 0, @size.r, 0, Math.PI*2, true
		ctx.lineWidth = w/256
		ctx.strokeStyle = 'yellow'
		ctx.stroke()
		ctx.closePath()

	drawJersey: (ctx) ->
		# Draw the player's jersey name (TODO) and number.
		ctx.textAlign = 'center'
		ctx.strokeStyle = 'white'
		ctx.fillStyle = 'white'
		ctx.font = "#{$.px .55*yards} sans"
		ctx.fillText @jersey.number.split(//).join("  "), 0,@size.r/2.0
		ctx.beginPath()
		ctx.moveTo 0,-@size.r
		ctx.lineTo 0,@size.r
		ctx.lineWidth = w/256
		ctx.stroke()
		ctx.closePath()

	drawBall: (ctx) ->
		# Draw a highlight around the player with the ball.
		ctx.beginPath()
		ctx.arc 0,0, @size.r, 0, Math.PI*2, true
		ctx.strokeStyle = 'brown'
		ctx.lineWidth = w/200
		ctx.stroke()
		ctx.closePath()

	draw: (ctx) ->
		super ctx
		if @ball? then @drawBall ctx
		if @highlighted then @drawHighlight ctx
		@drawJersey ctx


Formations =
	defense:
		"base":
			positions: [
				[0, -10], # Safety
				[-7, -2.5], [7, -2.5], # CB
				[-2, -4.5], [2, -4.5], # LB
				[-3, -1.5], [-1, -1.5], [1, -1.5], [3, -1.5], # DL
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


MouseEvent::position = -> $ @offsetX, @offsetY
TouchEvent::position = -> $ @touches[0].clientX, @touches[0].clientY

class ImpulseVector extends Entity
	constructor: ->
		super @
		@reset()
		teams = $.keysOf(Teams)
		canvas.bind 'mousedown', (evt) =>
			clock.start()
			if target = Circle.findAt(evt.position()...)
				whoseTurn = teams[Math.floor(turnCounter / MOVES_PER_TURN) % teams.length]
				if $.isType(FootballPlayer, target) and target.jersey.team isnt whoseTurn
					$.log "not your turn #{target.jersey.team}, it's #{whoseTurn}s"
					return
				@dragTarget = target
				@dragStart = @dragTarget.pos.x
				@dragEnd = @dragStart.slice()
				@dragTarget.highlighted = true
			evt.preventAll()
		canvas.bind 'touchcancel', (evt) =>
			@dragTarget?.highlighted = false
			@reset()
		canvas.bind 'mouseup, mouseout', (evt) =>
			@applyForce()
			evt.preventAll()
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
					@dragTarget.applyTorque 100, 10
					turnCounter++
				@dragTarget.highlighted = false
			else clock.stop()
		@reset()

	draw: (ctx) ->
		if @dragTarget and @dragEnd
			target = @dragTarget.pos.x
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

# Create the field itself, which draws the grass, lines, etc.
objects.push new FootballField().position(0,0).bounds(w,h)

$.log 'field created'

# Create the game ball
objects.push gameBall = new Football().position(w/2,h/2)
spawnFormation(lineOfScrimmageX,lineOfScrimmageY, Formations.defense["base"], 'red')
spawnFormation(lineOfScrimmageX,lineOfScrimmageY, Formations.offense["single-back"], 'blue')

$.log 'ball created'

objects.push new ImpulseVector()
