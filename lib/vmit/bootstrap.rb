require 'vmit'
require 'vmit/autoyast'
require 'vmit/kickstart'
require 'vmit/debian_preseed'

module Vmit

  module Bootstrap

    def self.arch
      Cheetah.run('arch', :stdout => :capture).strip
    end

    def self.bootstrapper_for(location)
      case
      when local_iso
      end
    end

    module MethodDebianPreseed
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        auto_install_args = {}
        preseed = Vmit::DebianPreseed.new

        Dir.mktmpdir do |floppy_dir|
          qemu_args = {:floppy => floppy_dir,
                      :append => "preseed/file=/floppy/preseed.cfg auto=true priority=critical",
                      :reboot => false}
          qemu_args.merge!(auto_install_args)
          # transform duplicates into an array
          qemu_args.merge!(args) do |key, oldv, newv|
            case key
              when :append then [oldv, newv].flatten
              else newv
            end
          end

          # Configure the autoinstallation profile to persist eth0
          # for the current MAC address
          # The interface will be setup with DHCP by default.
          # TODO: make this more flexible in the future?
          #autoyast.name_network_device(vm[:mac_address], 'eth0')
          File.write(File.join(floppy_dir, 'preseed.cfg'), preseed.to_txt)
          Vmit.logger.info "Preseed: 1st stage."
          vm.run(qemu_args)
          Vmit.logger.info "Preseed: 2st stage."
          # 2nd stage
          vm.run(:reboot => false)
        end
      end
    end

    module MethodKickstart
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        auto_install_args = {}
        kickstart = Vmit::Kickstart.new

        case media
          when Vmit::VFS::URI
            kickstart.install = location
          when Vmit::VFS::ISO
            kickstart.install = :cdrom
            auto_install_args.merge!(:cdrom => location.to_s)
          else raise ArgumentError.new("Unsupported autoinstallation: #{location}")
        end

        Dir.mktmpdir do |floppy_dir|
          qemu_args = {:floppy => floppy_dir,
                      :append => "ks=floppy repo=#{kickstart.install}",
                      :reboot => false}
          qemu_args.merge!(auto_install_args)
          # transform duplicates into an array
          qemu_args.merge!(args) do |key, oldv, newv|
            case key
              when :append then [oldv, newv].flatten
              else newv
            end
          end

          # Configure the autoinstallation profile to persist eth0
          # for the current MAC address
          # The interface will be setup with DHCP by default.
          # TODO: make this more flexible in the future?
          #autoyast.name_network_device(vm[:mac_address], 'eth0')
          File.write(File.join(floppy_dir, 'ks.cfg'), kickstart.to_ks_script)
          Vmit.logger.info "Kickstart: 1st stage."
          vm.run(qemu_args)
          Vmit.logger.info "Kickstart: 2st stage."
          # 2nd stage
          vm.run(:reboot => false)
        end
      end
    end

    module MethodAutoYaST
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        auto_install_args = {}
        auto_install_args.merge!(args)
        kernel_append_arg = case media
          when Vmit::VFS::URI then "install=#{location}"
          when Vmit::VFS::ISO then 'install=cdrom'
          else raise ArgumentError.new("Unsupported autoinstallation: #{location}")
        end
        auto_install_args.merge!(:append => kernel_append_arg)
        if media.is_a?(Vmit::VFS::ISO)
          auto_install_args.merge!(:cdrom => location.to_s)
        end

        Dir.mktmpdir do |floppy_dir|
          qemu_args = {:floppy => floppy_dir,
                      :append => "autoyast=device://fd0/autoinst.xml",
                      :reboot => false}
          # transform duplicates into an array
          qemu_args.merge!(auto_install_args) do |key, oldv, newv|
            case key
              when :append then [oldv, newv].flatten
              else newv
            end
          end

          autoyast = Vmit::AutoYaST.new

          # WTF SLE and openSUSE have different
          # base pattern names
          media.open('/content') do |content_file|
            content_file.each_line do |line|
              case line
                when /^DISTRIBUTION (.+)$/
                  case $1
                    when /SUSE_SLE/ then autoyast.minimal_sle!
                    when /openSUSE/ then autoyast.minimal_opensuse!
                  end
              end
            end
          end

          # Configure the autoinstallation profile to persist eth0
          # for the current MAC address
          # The interface will be setup with DHCP by default.
          # TODO: make this more flexible in the future?
          #autoyast.name_network_device(vm[:mac_address], 'eth0')
          File.write(File.join(floppy_dir, 'autoinst.xml'), autoyast.to_xml)
          Vmit.logger.info "AutoYaST: 1st stage."
          vm.run(qemu_args)
          Vmit.logger.info "AutoYaST: 2st stage."
          # 2nd stage
          vm.run(:reboot => false)
        end
      end
    end

    module SUSEMedia
      include MethodAutoYaST

      def get_initrd
        media.open("/boot/#{Vmit::Bootstrap.arch}/loader/initrd")
      end

      def get_kernel
        media.open("/boot/#{Vmit::Bootstrap.arch}/loader/linux")
      end
    end

    module FedoraMedia
      include MethodKickstart

      def get_initrd
        media.open("/images/pxeboot/initrd.img")
      end

      def get_kernel
        media.open("/images/pxeboot/vmlinuz")
      end
    end

    module DebianMedia
      include MethodDebianPreseed

      def get_initrd
        arch = Vmit::Bootstrap.arch.gsub(/x86_64/, 'amd64')
        media.open("/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/initrd.gz")
      end

      def get_kernel
        arch = Vmit::Bootstrap.arch.gsub(/x86_64/, 'amd64')
        media.open("/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/linux")
      end
    end

    # Boostraps a vm from a SUSE repository
    class FromMedia

      attr_reader :vm
      attr_reader :media
      attr_reader :location

      # @param [URI] location
      def self.accept?(location)
        # either a local ISO or a remote repository
        # (and not a remote file, but we don't have
        # a good way to check)
        Vmit::VFS::ISO.accept?(location) ||
          (Vmit::VFS::URI.accept?(location) &&
            File.extname(location.to_s) == '')
      end

      def initialize(vm, location)
        @location = location
        @vm = vm
        @media = Vmit::VFS.from(location)

        # TODO FIXME we need a clever way to detect the
        # location distro type. I could uname the kernel, but
        # I need the type to know the location.
        media_handler = case location.to_s.downcase
          when /fedora|redhat/ then FedoraMedia
          when /suse/ then SUSEMedia
          when /debian/ then DebianMedia
          else
            raise "Don't know how to bootstrap media #{location}"
        end
        self.extend media_handler

        @boot_kernel = get_kernel
        @boot_initrd = get_initrd
      end

      def execute
        args = {}
        args.merge!({:kernel => @boot_kernel.path, :initrd => @boot_initrd.path})
        execute_autoinstall(args)
      end
    end

    class FromImage

       # @param [URI] location
      def self.accept?(location)
        uri = case location
          when ::URI then location
          else ::URI.parse(location.to_s)
        end
        return false unless ['.raw', '.qcow2'].include?(File.extname(uri.to_s))
        uri.scheme == 'http' || File.exist?(uri.to_s)
      end

      def initialize(vm, location)
        @location = location
        #http://download.suse.de/ibs/Devel:/Galaxy:/Manager:/1.7:/Appliance/images/SUSE_Manager_Server_pg_Devel.x86_64-1.7.0-Build3.126.raw.xz
      end

      def execute
        Vmit.logger.info "From media!!!"
      end
    end

  end
end
