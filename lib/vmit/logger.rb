require 'logger'
require 'cheetah'

module Vmit

  # remote log service for
  # qemu ifup ifdown scripts
  class LogServer
    def method_missing(name, *args)
      Vmit.logger.send(name, *args)
    end
  end

  # Cheetah says it supports a logger
  # for debugging but then adds entries
  # with INFO instead of DEBUG
  class CheetahLoggerAdapter
    def initialize(logger)
      @logger = logger
    end

    def info(message)
      @logger.debug(message)
    end

    def error(message)
      @logger.error(message)
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
      Cheetah.default_options = {:logger => CheetahLoggerAdapter.new(logger)}
    end
    @logger
  end

end