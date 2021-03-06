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
require 'abstract_method'
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

    # The resource class. Resources with the
    # same class and name are considered to be
    # the same resource by the locking and refcounting
    # mechanism.
    #
    # For example, you may subclass RefcountedResource as
    # Network, and then have multiple Network subclasses, but
    # you can reimplement resource_class once in Network so that
    # all Network subclasses have the same resource class.
    #
    def resource_class
      (self.class.name.split('::').last || '').downcase
    end

    def initialize(name)
      @name = name
      # Allow the testcases to run as not root
      resource_dir = File.join(Vmit::RUN_DIR, 'resources')
      @lockfile_dir = File.join(resource_dir, resource_class, name)
      FileUtils.mkdir_p @lockfile_dir
      @lockfile_path = File.join(@lockfile_dir, 'lock')
    end

    # Creates a temporary resource with a random name
    # @return [RefcountedResource]
    def self.make_temp
      name = File.basename(Dir::Tmpname.make_tmpname([resource_class, 'tmp'],
                                                     File.join(resource_dir, resource_class)))
      new(name)
    end

    abstract_method :on_up
    abstract_method :on_down
    abstract_method :on_acquire
    abstract_method :on_release

    # Executes the given block.
    # @yield calling before on_up once per group of
    #   processes using the same resurce, and
    #   on_acquire before executing the block.
    #   It will execute on_release after executing the
    #   block and the last process using the reource
    #   will call on_down
    #
    def auto
      Vmit.logger.debug "Using resource lock #{lockfile_path}"
      File.open(lockfile_path, File::WRONLY | File::CREAT, 0666) do |f|
        begin
          if f.flock File::LOCK_EX | File::LOCK_NB
            # we are the first ones, bring the resource up
            on_up
          end

          if f.flock File::LOCK_SH
            on_acquire
          end

          yield if block_given?
        rescue => e
          Vmit.logger.error e.message
          raise e
        ensure
          if f.flock File::LOCK_EX | File::LOCK_NB
            on_down
          end
          on_release
          f.flock File::LOCK_UN
        end
      end
    rescue => e
      Vmit.logger.error e.message
      raise e
    ensure
      File.unlink(lockfile_path)
    end
  end
end
