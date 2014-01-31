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
require 'yaml'

module Vmit
  class Registry
    include Enumerable
  end

  # Wraps a registry providing buffered
  # semantics. All writes are buffered
  # until +save!+ is called.
  #
  # Changes in the wrapped registry for
  # already read keys are not reflected
  # until +reload!+ is called.
  #
  #   reg = ufferedRegistry.new(backing_registry)
  #   reg[:key1] = "value" # backing_registry not changed
  #   reg.save! # backing_registry changed
  #
  class BufferedRegistry < Registry
    def initialize(registry)
      @buffer = {}
      @registry = registry
    end

    def [](key)
      if not @buffer.has_key?(key)
        @buffer[key] = @registry[key]
      end
      @buffer[key]
    end

    def []=(key, val)
      @buffer[key] = val
    end

    def save!
      @buffer.each do |key, val|
        @registry[key] = val
      end
    end

    def reload!
      @buffer.keys.each do |key|
        @buffer[key] = @registry[key]
      end
    end
  end

  # Add types to keys
  # You need to inherit from this class
  #
  # @example
  #   class MyTypes < TypedRegistry
  #     type :key1, Fixnum
  #     type :key2, Float
  #   end
  #
  #   reg = MyTypes.new(backing_registry)
  #
  class TypedRegistry < Registry
    class << self
      def type(key, t=nil)
        @type_info ||= {}
        @type_info[key] = t unless t.nil?
        @type_info[key]
      end
    end

    def initialize(registry)
      @registry = registry
    end

    def type(key)
      self.class.type(key)
    end

    def [](key)
      rawval = @registry[key]
      case type(key).to_s
      when 'String' then rawval.to_s
      when 'Fixnum' then rawval.to_i
      when 'Float' then rawval.to_f
      else rawval
      end
    end

    def []=(key, val)
      if type(key)
        unless val.is_a?(type(key))
          fail TypeError.new("Expected #{type(key)} for #{key}")
        end
      end
      @registry[key] = val
    end
  end

  # Takes configuration options from a yml
  # file.
  class YamlRegistry < Registry
    def initialize(file_path)
      @file_path = file_path
      reload!
    end

    def reload!
      @data = YAML.load(File.read(@file_path))
    end

    def save!
      File.write(@file_path, @data.to_yaml)
    end

    def [](key)
      # YAML uses strings for keys
      # we use symbols.
      if @data.has_key?(key)
        @data[key]
      else
        @data[key.to_s]
      end
    end

    def []=(key, val)
      @data[key.to_s] = val
      save!
      reload!
    end

    def each(&block)
      Enumerator.new do |enum|
        @data.each do |key, val|
          enum.yield key.to_sym, val
        end
      end
    end

    def keys
      each.to_a.map(&:first)
    end
  end

  # Takes configuration options from a
  # filesystem tree where the files are
  # the keys and the content the values
  class FilesystemRegistry < Registry
    def initialize(base_path)
      @base_path = base_path
    end

    def [](key)
      begin
        path = File.join(@base_path, key.to_s)
        unless File.directory?(path)
          File.read(path)
        else
          return FilesystemRegistry.new(File.join(@base_path, path))
        end
      rescue Errno::ENOENT
        nil
      end
    end

    def []=(key, val)
      File.write(File.join(@base_path, key.to_s), val)
    end

    def each(&block)
      Enumerator.new do |enum|
        Dir.entries(@base_path).reject do |elem|
          ['.', '..'].include?(elem)
        end.each do |key|
          enum.yield key.to_sym, self[key]
        end
      end
    end

    def keys
      each.to_a.map(&:first)
    end
  end
end
