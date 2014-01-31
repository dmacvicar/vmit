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
require 'cheetah'
require 'drb'
require 'fileutils'
require 'stringio'
require 'yaml'
require 'confstruct'
# confstruct uses autoload, Deferred is
# not defined until you use Configuration
require 'confstruct/configuration'

require 'vmit/utils'

module Vmit
  class Workspace
    attr_accessor :work_dir

    VM_GLOBAL_DEFAULTS = {
      :memory => '1G',
      :kernel_cmdline => [],
      :virtio => true
    }
    SWITCH = 'br0'

    def self.from_pwd
      Vmit::Workspace.new(File.expand_path(Dir.pwd))
    end

    def name
      work_dir.downcase.gsub(/[^a-z\s]/, '_')
    end

    # Accessor to current options
    def [](key)
      @config[key]
    end

    def config_file
      File.join(work_dir, 'config.yml')
    end

    def initialize(work_dir)
      @config = Confstruct::Configuration.new(VM_GLOBAL_DEFAULTS.merge({
        :uuid => File.read('/proc/sys/kernel/random/uuid').strip,
        :mac_address => Vmit::Utils.random_mac_address
        }))
      @work_dir = work_dir

      if File.exist?(config_file)
        @config.configure(YAML.load(File.open(config_file)))
      end

      @network = config.lookup!('network', 'default')
      Vmit.logger.info "Network: #{@network}"
    end

    # @return [Array,<String>] sorted list of snapshots
    def disk_images
      Dir.glob(File.join(work_dir, '*.qcow2')).sort do |a, b|
        File.ctime(a) <=> File.ctime(b)
      end
    end

    # Takes a disk snapshot
    def disk_snapshot!
      disk_image_shift!
    end

    def disk_image_init!(opts = {})
      disk_image_shift!(opts)
    end

    DISK_INIT_DEFAULTS = { :disk_size => '10G' }

    # Shifts an image, adding a new one using the
    # previous newest one as backing file
    #
    # @param [Hash] opts options for the disk shift
    # @option opts [String] :disk_size Disk size. Only used for image creation
    def disk_image_shift!(opts = {})
      disk_config = Confstruct::Configuration.new(DISK_INIT_DEFAULTS)

      file_name = File.join(work_dir, "sda-#{Time.now.to_i}.qcow2")
      images = disk_images

      file_name = File.join(work_dir, 'base.qcow2') if images.size == 0

      args = ['/usr/bin/qemu-img', 'create',
              '-f', 'qcow2']

      if not images.empty?
        args << '-b'
        args << images.last
      end

      args << file_name
      if images.empty?
        args << disk_config.disk_size
      end

      Vmit.logger.info "Shifted image. Current is '#{file_name}'."
      Cheetah.run(*args)
    end

    # Rolls back to the previous snapshot
    def disk_rollback!
      images = disk_images

      return if images.empty?

      if images.size == 1
        Vmit.logger.fatal 'Only the base snapshot left!'
        return
      end
      Vmit.logger.info "Removing #{images.last}"
      FileUtils.rm(images.last)
    end

    # @returns [String] The latest COW snapshot
    def current_image
      curr = disk_images.last
      fail 'No hard disk image available' if curr.nil?
      curr
    end

    def options
      fail 'Workspace#options is deprecated.'
    end

    # @return [Hash] Config of the virtual machine
    #   This is all options plus the defaults
    def config
      @config
    end

    # @return [Hash] config that differs from default
    #  and therefore relevant to be persisted in config.yml
    def relevant_config
      config.diff(config.default_values)
    end

    # Saves the configuration in config.yml
    def save_config!
      if not relevant_config.empty?
        Vmit.logger.info 'Writing config.yml...'
        File.open(config_file, 'w') do |f|
          f.write(relevant_config.to_yaml)
        end
      end
    end

    def to_s
      config.to_s
    end

    BINDIR = File.join(File.dirname(__FILE__), '../../bin')
  end
end
