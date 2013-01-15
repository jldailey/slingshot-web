
# Interesting fact, an average lineman can apply about 16 Joules of force when bench pressing.
# This is my back of the envelope calculation based on benching 450 lbs (moving it 1 meter in 5 seconds).
# The strongest lineman I could find a number for, pressed 600 lbs, which is 24 J.
MIN_PLAYER_FORCE = 8 # Joules
MAX_PLAYER_FORCE = 24 # J
PLAYER_FORCE_DISTRIBUTION = [16, 2]

toKg = (lb) -> lb * 0.453592
toPounds = (kg) -> kg * 2.20462

# The smallest mass that the physics engine will deal with (avoiding divide by zero edge cases)
MIN_MASS_KG = 0.0001

weightTable =
	# each row is [mean, ssig] for the weight distribution of that position
	QB: [toKg(250), toKg(25)]
	HB: [toKg(280), toKg(25)]
	FB: [toKg(290), toKg(25)]
	WR: [toKg(220), toKg(25)]
	OL: [toKg(320), toKg(10)]


MEAN_PLAYER_KG = toKg(180)
MAX_PLAYER_KG = toKg(320)
randomPlayerWeight = -> $.random.gaussian

MIN_DRAG = 0.001
MAX_DRAG = 99999999999999

IMPULSE_FORCE_SCALE = 120
IMPULSE_TIME_SCALE = 100
PLAYER_DRAG = 12
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
gameField = null # created later
gameBall = null # created later
# $.log = $.throttle 50, $.log
$.log 'configured'

# This is the set of game objects (things that will tick and render in every frame)
window.objects = []
window.active = [] # the subset of objects that will tick() every frame
window.visible = [] # the subset of objects that will draw() every frame

# This clock drives the game loop.
window.clock = new Clock()
# It emits a 'tick' event at as close to 60 fps as it can.
clock.on 'tick', (dt) ->
	# This is the cental game loop:
	# First, we call .tick() on active objects so they can update state (position, etc)
	for obj in active
		obj.tick(dt)
	# Second, we draw visible items in every context.
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

# Draw a placeholder splash screen
context.each ->
	fillMultiLineText = (interval, lines...) =>
		for i in [0...lines.length] by 1
			@fillText lines[i], w/2, interval * (i+1)

	@fillStyle = 'black'
	@fillRect 0,0,w,h
	@fillStyle = 'white'
	@textAlign = 'center'
	@font = "#{$.px w/4} courier"
	fillMultiLineText h/5, " CLICK TO START".split(' ')...

$.log "splash screen drawn"

# Magic token that ends a dynamic force
class EndOfForce extends Error

window.dynamicGrapplingForce = (entB, maxRange=10.0) ->
	(entA) ->
		dx = entA.pos.x.minus(entB.pos.x)
		d = dx.magnitude()
		if d > maxRange
			throw new EndOfForce()
		else
			return d.scale(IMPULSE_FORCE_SCALE)

# Entity is the base class for all world objects; it handles physics, etc.
class Entity extends $.EventEmitter
	distance_cache = Object.create null # used to help collision detection
	@clearCaches = ->
		distance_cache = Object.create null
	@removeFromCache = (ent) ->
		unless ('guid' of ent and ent.guid of distance_cache)
			$.log "not removing #{ent.guid} from distance_cache (not present)"
			return
		for k,v of distance_cache[ent.guid]
			delete v[ent.guid]
		delete distance_cache[ent.guid]
	
	inactive: ->
		if (i = active.indexOf @) > -1
			active.splice i, 1
		@
	active: ->
		active.push @inactive()
		@
	invisible: ->
		if (i = visible.indexOf @) > -1
			visible.splice i, 1
		@
	visible: ->
		visible.push @invisible()
		@

	# property functions:
	fill: (f) -> @style.fill = f; @
	stroke: (s) -> @style.stroke = s; @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	drag: (c) ->
		@pos.drag = Math.min MAX_DRAG, Math.max MIN_DRAG, c
		@
	rotdrag: (c) ->
		@rot.drag = Math.min MAX_DRAG, Math.max MIN_DRAG, c
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
		@rot =
			x: 0
		@kg = MIN_MASS_KG # mass in kg
		@fullStop()
		objects.push @
		active.push @
		visible.push @

	# come to a complete and instant stop
	fullStop: ->
		@pos = x: @pos.x # preserve our current position
			v: $.zeros(@pos.x.length) # reset velocity
			a: $.zeros(@pos.x.length) # reset acceleration
			drag: MIN_DRAG
		@rot = x: @rot.x # preserve rotation
			v: 0 # reset angular velocity
			a: 0 # reset angular acceleration
			drag: MIN_DRAG
		@forces = Object.create null # the set of (temporary) forces on this object
		@torques = Object.create null
	
	momentum: ->
		@kg * @pos.v.magnitude()
	
	kineticEnergy: ->
		v = @pos.v.magnitude()
		.5 * @kg * v * v

	# get the distance between objects, using caching
	# suitable for use in [collision] loops in a single frame
	getDistance: (entB) ->
		a = @guid
		b = entB.guid
		if a of distance_cache and b of distance_cache[a]
			return distance_cache[a][b]
		distance_cache[a] or= Object.create null
		distance_cache[b] or= Object.create null
		distance_cache[a][b] = distance_cache[b][a] = @pos.x.minus(entB.pos.x).magnitude()

	# applies a temporary force to this entity
	applyForce: (duration, x...) ->
		if x.length is 1 and $.type(x[0]) in ['array','bling']
			x = x[0]
		$.log 'applying force', x, 'for', duration, 'ms'
		(@active().forces[$.now + duration] or= []).push x

	# applies a force function to this entity
	# the force function receives the entity to be forced, and returns a force vector
	applyDynamicForce: (duration, f) ->
		$.log 'applying dynamic force for ', duration, 'ms'
		(@active().forces[$.now + duration] or= []).push f

	applyTorque: (duration, t) ->
		$.log 'applying torque', t, 'for', duration
		(@active().torques[$.now + duration] or= []).push t

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
			for i in [0...forces.length] by 1
				force = forces[i]
				try
					total_force = total_force.plus switch $.type force
						when 'bling','array' then force
						when 'function' then force(@)
						else ($.log 'invalid force', force; [0,0])
				catch e
					$.log 'force failed:', force, ' error:', e
					forces.splice i, 1
					i -= 1

		# always include the drag force
		total_force = total_force.plus @pos.v.scale(-@pos.drag)

		return total_force

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
		if not isFinite(@rot.drag)
			$.log "DRAG rotted"
			@rot.drag = MIN_DRAG
		drag = @rot.v * -@rot.drag
		if drag isnt 0
			$.log 'torque decay', drag
		total_torque += @rot.v * -@rot.drag * @rot.drag
	
	# Adjust position (x,a,v) using vertlet integration:
	adjustPosition: (total_force, dt) ->
		@translate @pos.v.scale(dt).plus(@pos.a.scale(.5 * dt * dt))...  # 1. adjust the position based on current velocity plus some of the acceleration
		new_acceleration = total_force.scale(1/@kg) # 2. compute the new acceleration from total force
		@pos.v = @pos.v.plus(new_acceleration.plus(@pos.a).scale(.5)) # 3. adjust velocity based on two-frame average acceleration
		@pos.a = new_acceleration # 4. record acceleration for averaging
		if @pos.v.magnitude() is 0
			@inactive()

	# Adjust our rotation angle using a one-dimensional version of adjustPosition
	adjustRotation: (total_torque, dt) ->
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
		# total_torque = @getTotalTorque()

		@adjustPosition total_force, dts
		# @adjustRotation total_torque, dts


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
			.drag(MAX_DRAG)
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
		@getDistance(circleB) < (@size.r + circleB.size.r)
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
			.drag(PLAYER_DRAG)
			.rotdrag(MAX_DRAG)
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
		@drag(PLAYER_DRAG)
			.mass(PLAYER_MASS_KG)
			.radius(PLAYER_RADIUS)
			.team(team)
	toggleHighlight: ->
		@highlight = not @highlighted
	

	attemptGrapple: (other) ->
		@grapple.ing = other
		other.grapple.by = @
	attemptBreakGrapple: ->
		$.log 'attempting to break grapple'
		dx = @pos.x.minus(@grapple.by.pos.x)
		gap = dx.magnitude() - (@size.r + @grapple.by.size.r)
		@grapple.by.grapple.ing = null
		@grapple.by = null
		if gap < 0
			delta = dx.normalize().scale(-gap).scale(1.05) #.scale($.random.real(.6,1.4))
			@translate delta...
	
	# Become owner of the ball
	giveBall: (ball) ->
		$.log 'giving ball'
		return if ball.prevOwner is @
		(ball.owner = @).ball = ball

	# Relinquish ownership of any ball we are carrying.
	releaseBall: ->
		if @ball?
			$.log 'releasing ball'
			b = @ball
			b.prevOwner = @
			@ball = b.owner = null
			$.delay 500, =>
				if b.prevOwner is @ # unless it changed since we were scheduled
					b.prevOwner = null # clear off our previous ownership

	drawHighlight: (ctx) -> # Draw a highlight if we are marked as such.
		ctx.beginPath()
		ctx.arc 0, 0, @size.r, 0, Math.PI*2, true
		ctx.lineWidth = w/256
		ctx.strokeStyle = 'yellow'
		ctx.stroke()
		ctx.closePath()

	drawJersey: (ctx) -> # Draw the player's jersey number.
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

	drawBall: (ctx) -> # Draw a highlight around the player with the ball.
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

	tick: (dt) ->
		@checkCollision()
		super dt

	checkCollision: () ->
		for obj in objects
			# skip ourselves
			continue if obj.guid is @guid
			# pick up loose footballs we run over 
			switch obj.constructor
				when Football
					unless obj.owner? # if the ball is not owned
						if @overlaps(obj) # and we are touching it
							@giveBall(obj) # take it
				when FootballPlayer
					# skip (for now) people on our own team
					continue if obj.jersey.team is @jersey.team
					# if we are touching this other player
					if @overlaps(obj)
						# grapple them
						# @attemptGrapple(obj)
						obj.applyForce IMPULSE_TIME_SCALE, @pos.x.minus(obj.pos.x).scale(IMPULSE_FORCE_SCALE)

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

class Slingshot extends Entity
	constructor: ->
		super @
		@reset()
		teamNames = $.keysOf(Teams)
		canvas.bind 'mousedown', (evt) =>
			clock.start()
			if target = Circle.findAt(evt.position()...)
				whoseTurn = teamNames[Math.floor(turnCounter / MOVES_PER_TURN) % teamNames.length]
				if $.isType(FootballPlayer, target) and target.jersey.team isnt whoseTurn
					$.log "not your turn #{target.jersey.team}, it's #{whoseTurn}s"
					return
				@slingTarget = target
				@slingStart = @slingTarget.pos.x
				@slingEnd = @slingStart.slice()
				@slingTarget.highlighted = true
			evt.preventAll()
		canvas.bind 'touchcancel', (evt) =>
			@reset()
		canvas.bind 'mouseup, mouseout', (evt) =>
			@release()
			evt.preventAll()
		canvas.bind 'mousemove', (evt) =>
			@slingEnd = evt.position()
	reset: ->
		@slingTarget?.highlighted = false
		@slingTarget = @slingStart = @slingEnd = null
	
	# Releasing a loaded slingshot applies force to the slingTarget
	release: ->
		try
			if @slingTarget?
				force = @slingStart.minus(@slingEnd).scale(IMPULSE_FORCE_SCALE)
				if force.magnitude() > 0
					ok = true
					if $.isType Football, @slingTarget
						# a football with no owner cannot be moved
						unless @slingTarget.owner?
							ok and= false
						# and impulsing the ball is akin to throwing: it is removed from its owner
						@slingTarget.owner?.releaseBall()
					if ok
						@slingTarget.applyForce IMPULSE_TIME_SCALE, force...
						turnCounter++
					@slingTarget.highlighted = false
				else
					clock.stop()
			@reset()
		catch e
			console.error e

	draw: (ctx) ->
		if @slingTarget and @slingEnd
			target = @slingTarget.pos.x
			ctx.translate 0,0
			ctx.beginPath()
			ctx.moveTo target...
			ctx.lineTo target.minus(@slingEnd).plus(target)...
			ctx.lineWidth = w/128
			ctx.strokeStyle = 'white'
			if $.isType Football, @slingTarget
				if @slingTarget.owner?
					ctx.strokeStyle = 'yellow'
				else
					ctx.strokeStyle = 'red'
			ctx.stroke()
			ctx.closePath()

# Create the field itself, which draws the grass, lines, etc.
objects.push gameField = new FootballField().position(0,0).bounds(w,h)

$.log 'field created'

# Create the game ball
objects.push gameBall = new Football().position(w/2,h/2)

$.log 'ball created'

# Spawn two teams
spawnFormation(lineOfScrimmageX,lineOfScrimmageY, Formations.defense["base"], 'red')
spawnFormation(lineOfScrimmageX,lineOfScrimmageY, Formations.offense["single-back"], 'blue')

$.log "formations spawned"

# Create the slingshot
objects.push new Slingshot()

$.log "slingshot created"
