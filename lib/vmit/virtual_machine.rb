require 'cheetah'
require 'drb'
require 'fileutils'
require 'pidfile'
require 'stringio'
require 'yaml'

require 'vmit/utils'

module Vmit

  class VirtualMachine

    attr_accessor :work_dir

    VM_DEFAULTS = {
      :memory => '1G',
    }
    SWITCH = 'br0'

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

      @network = if @opts.has_key?(:network)
        Network.create(@opts[:network])
      else
        Vmit.logger.info 'No network selected. Using default.'
        Network.default
      end
      Vmit.logger.info "Network: #{@network}"
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

      Cheetah.run(*args)
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

    # @param [Hash] runtime_opts Runtime options
    #   @option runtime_opts [String] :cdrom CDROM image
    #   @option runtime_opts [String] :kernel Kernel image
    #   @option runtime_opts [String] :initrd initrd image
    #   @option runtime_opts [String] :append Kernel command line
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

        # advanced options, mostly to be used by plugins
        [:cdrom, :kernel, :initrd, :append].each do |key|
          if @opts.has_key?(key)
            args << "-#{key}"
            args << @opts[key]
          end
        end

        unless ENV['DISABLE_UUID']
          args << '-uuid'
          args << "#{@opts[:uuid]}"
        end

        DRb.start_service nil, self
        ENV['VMIT_SERVER'] = DRb.uri

        ENV['VMIT_SWITCH'] = SWITCH
        Vmit.logger.debug "Vmit server listening at #{DRb.uri}"

        @network.auto do
          Cheetah.run(*args)
        end
      rescue PidFile::DuplicateProcessError => e
        Vmit.logger.fatal "VM in '#{work_dir}'' is already running (#{e})"
      rescue Exception => e
        Vmit.logger.fatal e.message
        e.backtrace.each do |bt_line|
          Vmit.logger.debug "  #{bt_line}"
        end
      end
    end

    def ifup(device)
      Vmit.logger.info "  Bringing interface #{device} up"
      Cheetah.run '/sbin/ifconfig', device, '0.0.0.0', 'up'
      @network.connect_interface(device)
    end

    def ifdown(device)
      Vmit.logger.info "  Bringing down interface #{device}"
      Cheetah.run '/sbin/ifconfig', device, '0.0.0.0', 'down'
      @network.disconnect_interface(device)
    end
  end

end