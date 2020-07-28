require 'ostruct'

CONFIG = OpenStruct.new
optional_envs = %w(DOVETAIL_PROD_HOST)

# load env config
File.open("#{File.dirname(__FILE__)}/../../env-example", 'r').each_line do |line|
  unless line.strip.empty? || line[0] == '#'
    name = line.split('=').first
    CONFIG[name] = ENV[name] unless ENV[name].nil? || ENV[name].empty?
    abort "you must set #{name}" unless CONFIG[name] || optional_envs.include?(name)
  end
end
