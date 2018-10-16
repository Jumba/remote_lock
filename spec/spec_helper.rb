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

SPEC_STATS        = {}
SPEC_STAT_ENABLED = 'true' == ENV['SPEC_STAT']

RSpec.configure do |config|
  config.before(:each) do
    @__started = Time.now if SPEC_STAT_ENABLED
  end

  config.after(:each) do |example|
    if SPEC_STAT_ENABLED
      SPEC_STATS[example.full_description] = (Time.now.to_f - @__started.to_f).to_f
    end
  end

  config.after(:suite) do
    if SPEC_STAT_ENABLED
      puts "-----------------------"
      puts "Spec Performance Report"
      puts "-----------------------"
      
      SPEC_STATS.sort { |a, b| a.last <=> b.last }.each do |spec, took|
        puts "#{took.round(3).to_s} secs - #{(spec + "")}"
      end
    end
  end
end