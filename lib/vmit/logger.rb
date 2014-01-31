#
# Copyright (C) 2013 Duncan Mac-Vicar P. <dmacvicar@suse.de>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
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
      Cheetah.default_options = { :logger => CheetahLoggerAdapter.new(logger) }
    end
    @logger
  end
end
