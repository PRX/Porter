# SHELL = /bin/sh

all: check
ci: check

sam-build:
	sam build --use-container

check: lint test
lint: cfnlint prettier eslint typescript rubocop
test: minitest jest

cfnlint:
	cfn-lint --ignore-checks W --template template.yml

prettier:
	npm run prettier -- --check "**/*.{js,json,yaml,yml}"

eslint:
	npm run eslint -- "**/*.js"

typescript:
	npm run tsc

rubocop:
	bundle exec rubocop

minitest:
	bundle exec rake test

jest:
	npm test
