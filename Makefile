# SHELL = /bin/sh

# Containers own their dependencies and test runners, since they pin their own
# Ruby and may need tooling the repo root does not.
CONTAINER_DIRS := $(dir $(wildcard src/containers/*/Makefile))

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
test: minitest jest container-test

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

container-test:
	@for d in $(CONTAINER_DIRS); do $(MAKE) -C $$d test || exit 1; done

bootstrap:
	bundle install
	npm install
	pip3 install -r requirements.txt
	@for d in $(CONTAINER_DIRS); do $(MAKE) -C $$d bootstrap || exit 1; done
