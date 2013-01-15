
# Generate some players
#		With stats appropriate for various positions.
#	Score how well they fit that position
#	Sort by score
#	Simulate a draft
#		Each team picks the best remaining player in a position they haven't filled.
#		Positions to fill: QB, HB, WR, LB, CB, etc.
#	Store the resulting teams somewhere.


# Each player tracks some basic stats:
# - Weight
# - Speed
# - Strength

# Each position know
# - The gaussian distribution for each stat for each player in this position
#  - e.g., QB: { M: [toKg(200), 4], V: [9, 1], F: [16, 2] }
# - The ideal stats: (someday this should be a set of ideal cluster centers, so you can have an ideal scrambling QB vs an ideal throwing QB)

Positions =
	QB:
		kg: [230, 4]
		sp: [9, .5]
		st: [12, 2]

DraftOrder = ["QB", "QB"]
DraftPool = []

class Franchise
	constructor: (@city, @name) ->

Franchises = [
	new Franchise("New York", "Giants")
	new Franchise("Miami", "Dolphins")
]

class Player
	@generate = (position) ->
		position = Positions[position]
		p = new Player
		p.kg = $.random.gaussian(position.kg...)
		p.speed = $.random.gaussian(position.sp...)
		p.strength = $.random.gaussian(position.st...)

for i in [0...100] by 1
	DraftPool.push Player.generate("QB")

