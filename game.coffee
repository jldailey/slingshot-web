
body = document.body
aspect_ratio = 16 / 9
h = Math.max(body.scrollHeight, body.clientHeight)
w = h / aspect_ratio
canvas = $("canvas")
	.zap("height", h)
	.zap("width", w)
	.css
		position: "fixed"
		left: "50%"
		"margin-left": $.px(-w/2)
context = canvas.select('getContext').call('2d')
context.drawRect = (x,y,w,h,fill,stroke) ->
	@zap('fillStyle', fill)
		.zap('strokeStyle', stroke)
		.select('fillRect')
		.call(x,y,w,h)

context.drawRect 0,0, w,h, 'black'
context.drawRect w/4,h/4, w/2, h/2, 'gray'
context.each ->
	@fillStyle = 'black'
	@font = '20px sans-serif'
	@textAlign = 'center'
	@fillText 'Click', w/2, h/3

SpringForce = (x,y,k) ->
	(obj) ->
		$(obj.x - y,obj.y - y).scale(-k)

MIN_MASS_KG = 0.0001
MIN_DAMPING = 0.001
MAX_DAMPING = 9999999
IMPULSE_FORCE_SCALE = 6000
PLAYER_DAMPING = 600
class Entity
	constructor: ->
		@x = @y = @ax = @ay = @vx = @vy = 0
		@kg = 1.0
		@_damping = .00005
		@_lineWidth = 0
		@forces = Object.create null
	fill: (@_fill) -> @
	stroke: (@_stroke) -> @
	lineWidth: (@_lineWidth) -> @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	damping: (c) -> @_damping = Math.min(MAX_DAMPING, Math.max(MIN_DAMPING, c)); @
	applyForce: (x, y, duration) ->
		expires = $.now + duration
		(@forces[expires] or= []).push $(x,y)
	applyDynamicForce: (f, duration) ->
		expires = $.now + duration
		(@forces[expires] or= []).push f
	position: (@x, @y) -> @
	translate: (dx, dy) -> @x += dx; @y += dy; @
	tick: (dt) ->
		dts = dt/1000
		now = $.now
		total_force = $(0,0)
		for expires of @forces
			if now < expires
				for force in @forces[expires]
					total_force = total_force.plus switch $.type force
						when 'bling' then force
						when 'function' then force(@)
						else ($.log 'invalid force', force; [0,0])
			else
				delete @forces[expires]

		# damping force
		total_force = total_force.plus $(@vx,@vy).scale(-@_damping)

		# Velocity Vertlet integration applies accel->velocity->position
		dtsq = Math.pow(dts,2)
		@position(
			@x + (@vx * dts) + (.5 * @ax * dtsq),
			@y + (@vy * dts) + (.5 * @ay * dtsq)
		)
		new_acceleration = total_force.scale(1/@kg)
		avg_acceleration = new_acceleration.plus($(@ax,@ay)).scale(.5)
		@vx += avg_acceleration[0] * dts
		@vy += avg_acceleration[1] * dts


	draw: (ctx) ->
		if @_fill
			ctx.fillStyle = @_fill
			ctx.fill()
		if @_lineWidth
			ctx.lineWidth = @_lineWidth
		if @_stroke
			ctx.strokeStyle = @_stroke
			ctx.stroke()

class Rect extends Entity
	constructor: ->
		super @
		@w = @h = 0
	size: (@w, @h) -> @
	area: -> @w * @h
	draw: (ctx) ->
		ctx.beginPath()
		ctx.rect @x,@y,@w,@h
		ctx.closePath()
		Entity::draw.call @, ctx

class FootballField extends Rect
	constructor: ->
		super @
		@fill('green')
			.lineWidth(14)
			.stroke('black')
			.damping(MAX_DAMPING)
	draw: (ctx) ->
		ctx.beginPath()
		ctx.rect @x,@y,@w,@h
		ctx.closePath()
		Entity::draw.call @, ctx

class Text extends Entity
	text: (@_text) -> @
	font: (@_font) -> @
	textAlign: (@_textAlign) -> @
	draw: (ctx) ->
		if @_font then ctx.font = @_font
		if @_textAlign then ctx.textAlign = @_textAlign
		if @_fill then ctx.fillText @_text, @x, @y
		if @_stroke then ctx.strokeText @_stroke, @x, @y
		Entity::draw.call @, ctx

distance = (x1,y1,x2,y2) ->
	Math.sqrt (Math.pow(x2-x1, 2) + Math.pow(y2-y1, 2))

class window.Circle extends Entity
	instances = $()
	@get = (i) -> instances[i]
	@findAt = (x,y) ->
		instances.filter(-> distance(@x,@y,x,y) < @r).first()
	constructor: ->
		super @
		@r = 0
		instances.push @
	radius: (@r) -> @
	area: -> Math.PI * @r * @r
	draw: (ctx) ->
		ctx.beginPath()
		ctx.arc @x, @y, @r, 0, Math.PI*2, true
		ctx.closePath()
		Entity::draw.call @, ctx

Teams =
	red: ->
		@fill('red')
	blue: ->
		@fill('blue')
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
		context.each -> obj.draw @
clock.on 'started', -> $.log 'started'
clock.on 'stopped', -> $.log 'stopped'
objects.push new FootballField().position(0,0).size(w,h)
x = w/3
y = h/2
for _ in [0...5]
	objects.push new FootballPlayer('red').position(x,y)
	x += w/16
x = w/3
y += h/10
for _ in [0...5]
	objects.push new FootballPlayer('blue').position(x,y)
	x += w/16

dragging = false
dragTarget = dragStart = dragEnd = null
class DragTacker extends Entity
	constructor: ->
		super @
		@fill 'white'
		@stroke 'white'
	draw: (ctx) ->
		if dragTarget and dragEnd
			target = $(dragTarget.x, dragTarget.y)
			ctx.beginPath()
			ctx.moveTo target...
			ctx.lineTo target.plus(dragEnd.scale(-1)).plus(target)...
			ctx.lineWidth = w/128
			ctx.closePath()
			Entity::draw.call @, ctx
objects.push new DragTacker()
canvas.bind 'mousedown, touchstart', (evt) ->
	clock.start()
	$.log 'dragTarget', dragTarget = Circle.findAt(evt.offsetX, evt.offsetY)
	if dragTarget
		dragging = true
		dragStart = $ dragTarget.x, dragTarget.y
		dragEnd = dragStart.slice()
canvas.bind 'touchcancel', (evt) ->
	dragging = false
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mouseup, touchend', (evt) ->
	dragging = false
	if dragTarget
		delta = dragStart.plus(dragEnd.scale(-1)).scale(IMPULSE_FORCE_SCALE).push(100)
		dragTarget.applyForce delta...
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mousemove, touchmove', (evt) ->
	dragEnd = $(evt.offsetX, evt.offsetY)
