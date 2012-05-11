$: << File.join(File.dirname(__FILE__), "..", "lib")
require 'test/unit'
require 'vmit'

if ENV["DEBUG"]
  Vmitlogger = Logger.new(STDERR)
  Vmit.logger.level = Logger::DEBUG
end