scheduleFrame =
	window.requestAnimationFrame       or
	window.webkitRequestAnimationFrame or
	window.mozRequestAnimationFrame    or
	window.oRequestAnimationFrame      or
	window.msRequestAnimationFrame     or
	(cb) ->
		setTimeout callback, 1000 / 60

class window.Clock extends $.EventEmitter
	constructor: ->
		super @
		@started = 0
	start: ->
		t = @started = $.now
		f = =>
			t += (dt = $.now - t)
			if @started > 0
				@emit 'tick', dt
				scheduleFrame(f)
		scheduleFrame(f)
	stop: ->
		@started = 0
	toggle: ->
		if @started then @stop() else @start()

