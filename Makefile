.PHONY: help hooks-install

help:
	@printf '%s\n' \
		'Available targets:' \
		'  hooks-install  Activate the repository Git hooks'

hooks-install:
	git config --local core.hooksPath .githooks
