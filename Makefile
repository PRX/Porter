# SHELL = /bin/sh

all: clean check build
ci: check

clean:
	rm -rf .aws-sam

deploy: build deploy-check
	sam deploy --config-env=$(env)

build:
	sam build --use-container --parallel --cached

check: lint test
deploy-check: lint jest
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
