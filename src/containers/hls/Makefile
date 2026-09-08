bootstrap:
	bundle install

test:
	bundle exec ruby -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |f| require File.expand_path(f) }'

# make targets not associated with files
.PHONY: bootstrap test
