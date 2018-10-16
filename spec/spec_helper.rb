$:.unshift(File.dirname(__FILE__))
$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'remote_lock'
require 'redis'

require "rspec"
require "rspec/core"
require 'rspec/core/rake_task'
require 'yaml'
require 'pry'

Dir.glob(File.join(File.dirname(__FILE__), 'support/**/*.rb')).each do |file|
  require file
end

RSpec.configure do |config|
  config.before :each do
    redis.flushdb
  end

  config.filter_run_when_matching :focus
end
