##
# Wielder
#

NOSE := nose2

all:
	@echo targets:
	@echo \* test -- trigger testing

.PHONY: test
test: 
	${NOSE} --verbose --config ./test/nose2.cfg


