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
lint: cfnlint biome typescript standardrb
test: minitest jest

cfnlint:
	cfn-lint --ignore-checks W --template template.yml

biome:
	npm exec biome -- check

typescript:
	npm exec tsc

standardrb:
	bundle exec standardrb

minitest:
	bundle exec rake test

jest:
	npm test

bootstrap:
	bundle install
	npm install
	pip3 install -r requirements.txt
