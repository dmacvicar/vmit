require 'vmit/utils'
require 'yaml'
require 'stringio'
require 'pidfile'
require 'fileutils'
require 'drb'

module Vmit
  
  class VirtualMachine

    attr_accessor :work_dir

    VM_DEFAULTS = {
      :memory => '1G',      
    }

    def config_file
      File.join(work_dir, 'config.yml')
    end

    def initialize(work_dir)
      @work_dir = work_dir

      @opts = {}
      @opts.merge!(VM_DEFAULTS)

      if File.exist?(config_file)
        @opts.merge!(YAML::load(File.open(config_file)))
      end

      # By default the following keys are useful to be 
      # generated if they don't exist and then use the
      # same in the future UNLESS they are
      # overriden with vmit run
      if not @opts.has_key?(:mac_address)
        @opts[:mac_address] = Vmit::Utils.random_mac_address
      end

      if not @opts.has_key?(:uuid)
        @opts[:uuid] = File.read("/proc/sys/kernel/random/uuid").strip
      end
      
    end

    # @return [Array,<String>] sorted list of snapshots
    def disk_images
      Dir.glob(File.join(work_dir, '*.qcow2')).sort do |a,b|
        File.ctime(a) <=> File.ctime(b)
      end
    end

    def disk_snapshot!
      disk_image_shift!
    end

    def disk_image_init!(opts={})
      disk_image_shift!(opts)
    end

    DISK_INIT_DEFAULTS = {:disk_size => '10G'}

    # Shifts an image, adding a new one using the
    # previous newest one as backing file
    #
    # @param [Hash] opts options for the disk shift
    # @option opts [String] :disk_size Disk size. Only used for image creation
    def disk_image_shift!(opts={})
      runtime_opts = DISK_INIT_DEFAULTS.merge(opts)

      file_name = File.join(work_dir, "sda-#{Time.now.to_i}.qcow2")
      images = disk_images

      file_name = 'base.qcow2' if images.size == 0

      args = ['/usr/bin/qemu-img', 'create',
        '-f', "qcow2"]
      
      if not images.empty?
        args << '-b'
        args << images.last
      end
      args << file_name
      if images.empty?
        args << runtime_opts[:disk_size]
      end
  
      Vmit::Utils.run_command(*args)
    end

    def disk_rollback!
      images = disk_images
      
      return if images.empty?

      if images.size == 1
        Vmit.logger.fatal "Only the base snapshot left!"
        return
      end
      Vmit.logger.info "Removing #{images.last}"
      FileUtils.rm(images.last)
    end

    def current_image
      curr = disk_images.last
      raise "No hard disk image available" if curr.nil?
      curr
    end

    def options
      @opts
    end

    # @return [Hash] Config of the virtual machine
    #   This is all options plus the defaults
    def config
      VM_DEFAULTS.merge(@opts)
    end

    # @return [Hash] config that differs from default
    #  and therefore relevant to be persisted in config.yml
    def relevant_config
      config.diff(VM_DEFAULTS)
    end

    # Saves the configuration in config.yml
    def save_config!
      if not relevant_config.empty?
        Vmit.logger.info "Writing config.yml..."
        File.open(config_file, 'w') do |f|
          f.write(relevant_config.to_yaml)
        end
      end
    end

    def to_s
      config.to_s
    end

    BINDIR = File.join(File.dirname(__FILE__), '../../bin')

    def run(runtime_opts)
      
      Vmit.logger.info "Starting VM..."
      @opts.merge!(runtime_opts)

      config.each do |k,v|
        Vmit.logger.info "  => #{k} : #{v}"
      end

      begin
        ifup = File.expand_path(File.join(BINDIR, 'vmit-ifup'))
        ifdown = File.expand_path(File.join(BINDIR, 'vmit-ifdown'))

        PidFile.new(:piddir => work_dir, :pidfile => "qemu.pid")
        args = ['/usr/bin/qemu-kvm', '-boot', 'c',
            '-drive', "file=#{current_image},if=virtio",
            '-m', "#{@opts[:memory]}",
            '-net', "nic,macaddr=#{@opts[:mac_address]}",
            '-net', "tap,script=#{ifup},downscript=#{ifdown}"]
        if @opts.has_key?(:cdrom)
          args << '-cdrom'
          args << @opts[:cdrom]
        end

        unless ENV['DISABLE_UUID']
          args << '-uuid'
          args << "#{@opts[:uuid]}"
        end

        #Vmit::Utils.setup_network!

        DRb.start_service nil, Vmit::LogServer.new
        ENV['VMIT_LOGSERVER'] = DRb.uri
        ENV['VMIT_SWITCH'] = 'br0'
        Vmit.logger.debug "Log server listening at #{DRb.uri}"

        Vmit::Utils.run_command(*args)
      rescue PidFile::DuplicateProcessError => e
        Vmit.logger.fatal "VM in '#{work_dir}'' is already running (#{e})"
      rescue Exception => e
        Vmit.logger.fatal e.message
      end
    end

  end

end