COFFEE=node_modules/.bin/coffee
COFFEEJS=js/coffee-script.js
BLING=node_modules/bling/dist/bling.js
BLINGJS=js/bling.js
D3JS=js/d3.js
LESSJS=js/less.js
LESSC=node_modules/.bin/lessc
MOCHA=node_modules/.bin/mocha
MOCHA_OPTS=--compilers coffee:coffee-script --globals document,window,Bling,$$,_ -R dot
SRC_FILES=$(shell ls coffee/*.cup)
TEST_FILES=$(shell ls test/*.cup 2> /dev/null)
FILTER_COMMENTS=grep -v '^\s*\# ' | perl -ne 's/^\s*[\#]/\#/p; print'
PREPROC=cpp

all: js/game.js css/style.css $(COFFEEJS) $(BLINGJS) $(LESSJS)

test: all test/pass
	@echo "All tests are passing."

test/pass: $(MOCHA) $(SRC_FILES) $(TEST_FILES)
	$(MOCHA) $(MOCHA_OPTS) $(TEST_FILES) && touch test/pass

js:
	mkdir -p js

js/game.js: js $(SRC_FILES) $(COFFEE) Makefile
	@mkdir -p stage js
	@for file in $(SRC_FILES); do mkdir -p stage/`dirname $$file` ; cat $$file | $(FILTER_COMMENTS) > stage/$$file; done
	@(cd stage/coffee && cat game.cup | $(PREPROC) | ../../$(COFFEE) -sc > ../../$@)

css/style.css: css/style.less $(LESSC)
	$(LESSC) $< $@

$(COFFEEJS): js $(COFFEE)
	curl http://coffeescript.org/extras/coffee-script.js > $@
	touch $@

$(COFFEE):
	npm install coffee-script
	# PATCH: avoid a warning message from the coffee compiler
	sed -ibak -e 's/path.exists/fs.exists/' node_modules/coffee-script/lib/coffee-script/command.js
	rm -f node_modules/coffee-script/lib/coffee-script/command.js.bak

$(BLING):
	npm install bling

$(BLINGJS): $(BLING)
	cp $(BLING) $@

$(MOCHA):
	npm install mocha

$(D3JS):
	curl http://d3js.org/d3.v2.min.js > $@

$(LESSJS):
	curl https://raw.github.com/cloudhead/less.js/master/dist/less-1.3.3.min.js > $@

$(LESSC):
	npm install less

clean:
	rm -rf js
	rm -rf node_modules
