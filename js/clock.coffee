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
		return if @started
		t = @started = $.now
		f = =>
			t += (dt = $.now - t)
			if @started > 0
				@emit 'tick', dt
				scheduleFrame(f)
		scheduleFrame(f)
		@emit 'started'
	stop: ->
		@started = 0
		@emit 'stopped'
	toggle: ->
		if @started then @stop() else @start()

