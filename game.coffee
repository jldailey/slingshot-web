
body = document.body
aspect_ratio = 16 / 9
h = Math.max(body.scrollHeight, body.clientHeight)
w = h / aspect_ratio

# w and h are the real-pixel heights of the canvas
# we also need a conversion from pixels to yards and back
# for now, we just assume that the play area is 40yds long
yards = h/40
# so, (10*yards) is the number of pixels in 10 yards
# and (10/yards) is the number of yards in 10 pixels


# Create the canvas to draw on
canvas = $("canvas")
	.zap("height", h)
	.zap("width", w)
	.css # center the canvas
		position: "fixed"
		left: "50%"
		"margin-left": $.px(-w/2)

# Create the drawing context
context = canvas.select('getContext').call('2d')

SpringForce = (x,y,k) ->
	(obj) ->
		$(obj.x - y,obj.y - y).scale(-k)

MIN_MASS_KG = 0.0001
MIN_DAMPING = 0.001
MAX_DAMPING = 9999999
IMPULSE_FORCE_SCALE = 130
PLAYER_DAMPING = 11

_tmp_log_limit = 0

# Entity is the base class for all world objects; it handles physics, etc.
class Entity
	constructor: ->
		@x = $.zeros(2) # position in m
		@a = $.zeros(2) # acceleration in m/s^2
		@v = $.zeros(2) # velocity in m/s
		@kg = MIN_MASS_KG # mass in kg
		@_damping = MIN_DAMPING # damping coefficient (unitless)
		@forces = Object.create null # the set of forces applied to this object
	fill: (@_fill) -> @
	stroke: (@_stroke) -> @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	damping: (c) -> @_damping = Math.min(MAX_DAMPING, Math.max(MIN_DAMPING, c)); @
	applyForce: (duration, x...) ->
		$.log "applying force: #{x} for duration: #{duration}"
		expires = $.now + duration
		(@forces[expires] or= []).push x
	applyDynamicForce: (duration, f) ->
		expires = $.now + duration
		(@forces[expires] or= []).push f
	position: (x...) -> @x = $ x; @
	translate: (dx...) ->
		for i in [0...dx.length] by 1
			if (not isFinite(dx[i])) or Math.abs(dx[i]) < .01
				dx[i] = 0
		if dx[0] isnt 0 or dx[1] isnt 0
			$.log dx[0], dx[1]
			@x = @x.plus(dx); @
	tick: (dt) ->
		dts = dt/1000 # convert time to seconds; so physics works in m/s
		now = $.now

		# Add up all the forces on this object
		total_force = $.zeros(2)

		# Temporary forces are organized by expiration time
		for expires,forces of @forces
			if now >= expires # if they are expired, just clean them out
				$.log "expiring force"
				delete @forces[expires]
				continue
			# otherwise, add up all the forces in this time bucket
			for force in forces
				$.log "adding force"
				total_force = total_force.plus switch $.type force
					when 'bling','array' then force
					when 'function' then force(@)
					else ($.log 'invalid force', force; [0,0])

		# always include the damping force
		total_force = total_force.plus @v.scale(-@_damping)

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

distance = (x1,y1,x2,y2) ->
	Math.sqrt (Math.pow(x2-x1, 2) + Math.pow(y2-y1, 2))

class window.Circle extends Entity
	instances = $()
	@get = (i) -> instances[i]
	@findAt = (x...) ->
		instances.filter((-> @x.minus(x).magnitude() < @r), 1).first()
	constructor: ->
		super @
		@r = 0
		instances.push @
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

class window.FootballPlayer extends Circle
	team: (@_team) -> Teams[@_team]?.call @; @
	constructor: (team) ->
		super @
		@damping(PLAYER_DAMPING)
			.mass(100) # 220 lbs
			.radius(w/48)
			.team(team)

objects = []
window.clock = new Clock()
clock.on 'tick', (dt) ->
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

Formations =
	defense:
		"4-3": [
			[-5, -10], [5, -10], # FS + SS
			[-9, -2.5], [9, -2.5], # CB x 2
			[-4, -4.5], [0, -4.5], [4, -4.5], # LB x 3
			[-3, -1.5], [-1, -1.5], [1, -1.5], [3, -1.5], # DL x 4
		]
	offense:
		"single-back": [
			[-4,0.5], [-2,0.5], # LG,LT
			[4,0.5],[2,0.5], # RG,RT
			[0,0.5], # C
			[0,1.5], # QB
			[0,4.5], # HB
			[-8,1.5], [8,1.5], # WR
		]
spawnFormation = (x,y,formation, team) ->
	for pos in formation
		objects.push new FootballPlayer(team).position(pos[0]*yards+x,pos[1]*yards+y)

spawnFormation(w/2,h/1.5, Formations.defense["4-3"], 'red')
spawnFormation(w/2,h/1.5, Formations.offense["single-back"], 'blue')

dragging = false
dragTarget = dragStart = dragEnd = null
class ImpulseVector extends Entity
	constructor: ->
		super @
	draw: (ctx) ->
		if dragTarget and dragEnd
			target = dragTarget.x
			ctx.translate 0,0
			ctx.beginPath()
			ctx.moveTo target...
			ctx.lineTo target.minus(dragEnd).plus(target)...
			ctx.lineWidth = w/128
			ctx.strokeStyle = 'white'
			ctx.stroke()
			ctx.closePath()
objects.push new ImpulseVector()
canvas.bind 'mousedown, touchstart', (evt) ->
	clock.start()
	$.log 'dragTarget', dragTarget = Circle.findAt(evt.offsetX, evt.offsetY)
	if dragTarget
		dragging = true
		dragStart = dragTarget.x
		dragEnd = dragStart.slice()
canvas.bind 'touchcancel', (evt) ->
	dragging = false
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mouseup, touchend', (evt) ->
	dragging = false
	if dragTarget
		delta = dragStart.minus(dragEnd).scale(IMPULSE_FORCE_SCALE)
		dragTarget.applyForce 100, delta...
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mousemove, touchmove', (evt) ->
	dragEnd = $(evt.offsetX, evt.offsetY)
