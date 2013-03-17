
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
      @buffer = Hash.new
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
        @type_info ||= Hash.new
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
          raise TypeError.new("Expected #{type(key)} for #{key}")
        end
      end
      @registry[key] = val
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