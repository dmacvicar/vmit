require 'tmpdir'

module Vmit

  # This class allows to bring a resource represented
  # by a shared lock file only once by the
  # the first process using it, and down when the
  # last process finishes.
  #
  # Think of it as the first one that enters the room
  # turn the lights on, and the last one that exits,
  # turns the lights off.
  #
  # Call:
  #
  # on_up : will bring the resource up if needed
  # on_down: will bring tthe resource down if no more users
  # on_acquire: will start using the resource
  # on_release: will stop using the resource
  #
  # Then use the class like this:
  #
  # YourRefCountedResource.auto('name') do
  #   # do something
  # end
  #
  class RefcountedResource

    attr_reader :name
    attr_reader :lockfile_path
    attr_reader :lockfile_dir

    def auto
      begin
        Vmit.logger.debug "Using resource lock #{lockfile_path}"
        File.open(lockfile_path, File::WRONLY | File::CREAT, 0666) do |f|
          begin
            if f.flock File::LOCK_EX | File::LOCK_NB
              # we are the first ones, bring the resource up
              self.on_up
            end

            if f.flock File::LOCK_SH
              self.on_acquire
            end

            yield if block_given?
          rescue Exception => e
            Vmit.logger.error e.message
            raise e
          ensure
            if f.flock File::LOCK_EX | File::LOCK_NB
                self.on_down
            end
            on_release
            f.flock File::LOCK_UN
          end
        end
      rescue Exception => e
        Vmit.logger.error e.message
        raise e
      ensure
        File.unlink(lockfile_path)
      end
    end

    def initialize(name)
      @name = name
      # Allow the testcases to run as not root
      resource_dir = File.join(Vmit::RUN_DIR, 'resources')
      class_dir = (self.class.name.split('::').last || '').downcase
      @lockfile_dir = File.join(resource_dir, class_dir, name)
      FileUtils.mkdir_p @lockfile_dir
      @lockfile_path = File.join(@lockfile_dir, 'lock')
      #@lockfile_path = '/tmp/vmit-lock'
    end

    def on_up
      raise NotImplementedError
    end

    def on_down
      raise NotImplementedError
    end

    def on_acquire
      raise NotImplementedError
    end

    def on_release
      raise NotImplementedError
    end

  end

end