require 'bling'
fs = require 'fs'
sys = require 'sys'
inputFile = '2002_nfl_pbp_data.csv'
brainFile = inputFile.replace /.csv$/, '.brain'

# Train a play calling brain.
# Input: qtr, min, sec, down, togo, ydline
# Output: run, pass, kick
brain = new (require 'brain').NeuralNetwork(
	hiddenLayers: [10, 10]
	learningRate: .1
)
trainingOptions = {
	iterations: 10000
	errorThresh: .05
}
try
	$.log "Reading brain data from #{brainFile}..."
	data = fs.readFileSync brainFile
	$.log data.length
	brain.fromJSON JSON.parse data.toString()
catch e
	$.log e

classify = (desc) ->
	return switch true
		when /^\s*$/.test desc then 'other'
		when /extra point/.test desc then 'other'
		when /TWO-POINT CONVERSION/.test desc then 'other'
		when /PENALTY/.test desc then 'other'
		when /FUMBLE/.test desc then 'other'
		when /INTERCEPT/.test desc then 'pass'
		when /kicks/.test desc then 'kick'
		when /field goal/.test desc then 'kick'
		when /pass/.test desc then 'pass'
		else 'run'

suffixes = ['th', 'st','nd','rd','th']

trainingData = []

$.log "Opening #{inputFile}..."
fs.readFile inputFile, (err, data) ->
	$.log "Read #{data.length} bytes"
	lines = $(data.toString().split '\n')
	$.log "Read #{lines.length} lines"
	prevKind = null
	for line in lines.skip(1)
		[gameid,
			qtr, min, sec,
			offense,defense,
			down,togo,ydline,
			description,offscore,defscore,
			season
		] = line.split ','
		[date,away,home] = gameid.split /[_@]/

		continue unless offense is 'NYG'
		continue unless description?
		kind = classify(description)
		continue if kind is 'other'
		# $.log "#{home} vs #{away} (Q#{qtr} #{min}:#{sec}) #{down}#{suffixes[down]} & #{togo} @ #{ydline} : #{kind}"
		down = parseFloat down
		continue unless isFinite down
		qtr = parseFloat qtr
		continue unless isFinite qtr
		togo = parseFloat togo
		continue unless isFinite togo
		min = parseFloat min
		continue unless isFinite min
		sec = parseFloat sec
		continue unless isFinite sec
		trainingData.push {
			input: { q: qtr, t: min+(sec/60), d:down, y: togo, p: + (prevKind is 'run')}
			output: {
				run: + (kind is 'run')
				pass: + (kind is 'pass')
			}
		}
		prevKind = kind

	for i in [0...100]
		$.log "Training brain with #{trainingData.length} plays..."
		start = $.now
		ret = brain.train trainingData, trainingOptions
		ret.elapsed = $.now - start
		$.log ret
		$.log brain.run {q:1, t: 50, d: 1, y: 10}
		$.log brain.run {q:1, t: 1, d: 3, y: 10}
		# if isFinite ret.error then fs.writeFile brainFile, JSON.stringify brain.toJSON()
		$.log "Rate: #{ret.iterations * 1000 / ret.elapsed} per sec."

