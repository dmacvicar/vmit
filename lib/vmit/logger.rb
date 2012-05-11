require 'logger'

module Vmit

  # remote log service for
  # qemu ifup ifdown scripts
  class LogServer
    def method_missing(name, *args)
      Vmit.logger.send(name, *args)
    end
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.logger
    if @logger.nil?
      logger = Logger.new(STDERR)
      logger.level = Logger::INFO
      logger.level = Logger::DEBUG if ENV['DEBUG']
      Vmit.logger = logger      
    end
    @logger
  end

end