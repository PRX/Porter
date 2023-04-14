# frozen_string_literal: true

require "rake/testtask"
require "dotenv"

Dotenv.load

Rake::TestTask.new("test") do |t|
  t.libs << "test/support"
  t.pattern = "test/**/*_test.rb"
end

task default: :test
