# frozen_string_literal: true

require 'minitest/reporters'
require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/pride'
require 'minitest/focus'
require 'config'
begin begin
        require 'pry'
      rescue StandardError
        LoadError
      end end
# output format
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
