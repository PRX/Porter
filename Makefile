sam_build:
	sam build --use-container

ci: lint test
lint: cfnlint prettier eslint typescript rubocop
test: ruby_tests node_tests

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

ruby_tests:
	bundle exec rake test

node_tests:
	npm test
