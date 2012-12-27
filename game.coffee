
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

springForce = (x,y,k) ->
	(obj) ->
		$(obj.x - y,obj.y - y).scale(-k)

distance = (x,y) ->
	x.plus(y.scale(-1)).magnitude()

MIN_MASS_KG = 0.0001
MIN_DAMPING = 0.001
MAX_DAMPING = 9999999
IMPULSE_FORCE_SCALE = 6000
PLAYER_DAMPING = 600
class Entity
	instances = $()
	@get = (i) -> instances[i]
	@findNear = (x,y) ->
		x = $ x,y
		instances.filter(-> distance(@x,x) < @r)
	constructor: ->
		@x = $.zeros(2)
		@a = $.zeros(2)
		@v = $.zeros(2)
		@kg = MIN_MASS_KG
		@_damping = MIN_DAMPING
		@_lineWidth = 0
		@_scale = 1.0
		@_rotate = 0.0
		@forces = Object.create null
		instances.push @
	fill: (@_fill) -> @
	stroke: (@_stroke) -> @
	lineWidth: (@_lineWidth) -> @
	scale: (@_scale) -> @
	rotate: (@_rotate) -> @
	mass: (kg) -> @kg = Math.max(MIN_MASS_KG,kg); @
	damping: (c) -> @_damping = Math.min(MAX_DAMPING, Math.max(MIN_DAMPING, c)); @
	applyForce: (duration, x...) ->
		expires = $.now + duration
		(@forces[expires] or= []).push $(x)
	applyDynamicForce: (f, duration) ->
		expires = $.now + duration
		(@forces[expires] or= []).push f
	position: (x...) -> @x = $(x); @
	translate: (dx...) -> @x = @x.plus dx; @
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
		total_force = total_force.plus @v.scale(-@_damping)

		# Velocity Vertlet integration applies accel->velocity->position
		dtsq = Math.pow(dts,2)
		@x.plus(@v.scale(dts).plus(@a.scale .5 * dtsq))

		# @position(
			# @x + (@vx * dts) + (.5 * @ax * dtsq),
			# @y + (@vy * dts) + (.5 * @ay * dtsq)
		# )
		new_acceleration = total_force.scale(1/@kg)
		avg_acceleration = new_acceleration.plus(@a).scale(.5)
		@v.plus(avg_acceleration.scale(dts))

	preDraw: (ctx) ->
		if @x.magnitude() isnt 0
			ctx.translate @x.first(2)...
		if @_scale isnt 1.0
			ctx.scale @_scale
		if @_rotate isnt 0
			ctx.rotate @_rotate
		if @_fill
			ctx.fillStyle = @_fill
		if @_lineWidth
			ctx.lineWidth = @_lineWidth
		if @_stroke
			ctx.strokeStyle = @_stroke
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
			.size(60,100)
	draw: (ctx) ->
		# A field should be:
		# 10m: end zone
		# 100m: lines
		# 7m: score board
		# 3m: play/pause
		super ctx
		ctx.beginPath()
		for y in [10..100] by 10
			ctx.moveTo 0,y
			ctx.lineTo @w,y
		ctx.lineWidth = .1
		ctx.strokeStyle = 'white'
		ctx.stroke()
		ctx.closePath()


class Text extends Entity
	text: (@_text) -> @
	font: (@_font) -> @
	textAlign: (@_textAlign) -> @
	draw: (ctx) ->
		if @_font then ctx.font = @_font
		if @_textAlign then ctx.textAlign = @_textAlign
		if @_fill then ctx.fillText @_text, 0, 0
		if @_stroke then ctx.strokeText @_stroke, 0, 0
		super ctx

trs =
	'click': 'Click'
tr = (t) -> trs[t] ? t
class Label extends Text
	constructor: (@_code) ->
		super @
	draw: (ctx) ->
		@_text = tr @_code

class window.Circle extends Entity
	constructor: ->
		super @
		@r = 0
	radius: (@r) -> @
	area: -> Math.PI * @r * @r
	draw: (ctx) ->
		ctx.beginPath()
		ctx.arc 0, 0, @r, 0, Math.PI*2, true
		ctx.closePath()
		super ctx

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
			.radius(.5) # in meters
			.team(team)

objects = []
window.clock = new Clock()
window.camera =
	position: $.zeros(2).plus([5,10])
	zoom: 3.0
	rotate: 0.0
clock.on 'tick', (dt) ->
	for obj in objects
		obj.tick(dt)
	for obj in objects
		context.each ->
			@save()
			@scale w/(60/camera.zoom), h/(100/camera.zoom)
			@translate camera.position.scale(-1)...
			@rotate camera.rotation
			obj.preDraw @
			obj.draw @
			@restore()
clock.on 'started', -> $.log 'started'
clock.on 'stopped', -> $.log 'stopped'
objects.push new FootballField().position(0,0)
for x in [10..50] by 5
	objects.push new FootballPlayer('red').position x, 40
	objects.push new FootballPlayer('blue').position x, 60

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
			super ctx
objects.push new DragTacker()

canvas.bind 'mousedown touchstart', (evt) ->
	clock.start()
	if dragTarget
		$.log 'dragTarget', dragTarget = Circle.findNear(evt.offsetX, evt.offsetY).first()
		dragging = true
		dragStart = $ dragTarget.x, dragTarget.y
		dragEnd = dragStart.slice()
canvas.bind 'touchcancel', (evt) ->
	dragging = false
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mouseup touchend', (evt) ->
	dragging = false
	if dragTarget
		impulse = dragStart
			.plus(dragEnd.scale(-1)) # from end to start
			.scale(IMPULSE_FORCE_SCALE)
		dragTarget.applyForce 100, impulse... # applied to the object
	dragTarget = dragStart = dragEnd = null
canvas.bind 'mousemove touchmove', (evt) ->
	dragEnd = $(evt.offsetX, evt.offsetY)
