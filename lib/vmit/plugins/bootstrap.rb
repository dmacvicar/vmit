require 'vmit/autoyast'
require 'abstract_method'
require 'clamp'
require 'net/http'
require 'tmpdir'

module Vmit
  module Bootstrap

    # Base class for bootstrap methods
    class Method
    end

    module MethodAutoYaST
      # @param [Hash] args Arguments for 1st stage
      def execute_autoyast(args)
        Dir.mktmpdir do |floppy_dir|

          qemu_args = {:floppy => floppy_dir,
                      :append => "autoyast=device://fd0/autoinst.xml",
                      :reboot => false}
          # transform duplicates into an array
          qemu_args.merge!(args) do |key, oldv, newv|
            case key
              when :append then [oldv, newv].flatten
              else newv
            end
          end

          autoyast = Vmit::AutoYaST.new
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

    # Boostraps a vm from a SUSE repository
    class MethodRepo

      attr_reader :vm

      include MethodAutoYaST

      def initialize(vm, repo)
        # it is a directory, and URI.join sucks
        repo_s = case
          when repo.end_with?('/') then repo
          else repo + '/'
        end
        @repo_uri = URI.parse(repo_s)
        @vm = vm
      end

      def execute
        arch = 'x86_64'

        Dir.mktmpdir do |dir|
          kernel = File.join(dir, 'linux')
          initrd = File.join(dir, 'initrd')

          Vmit::Utils.download_file(URI.join(@repo_uri,
                                    "boot/#{arch}/loader/linux"), kernel)
          Vmit::Utils.download_file(URI.join(@repo_uri,
                                    "boot/#{arch}/loader/initrd"), initrd)

          kernel_size = File.size?(kernel)
          initrd_size = File.size?(initrd)

          if ! (kernel_size && initrd_size)
            Vmit.logger.error "Can't download kernel & initrd"
            return 1
          end

          Vmit.logger.info "kernel: #{Vmit::Utils.kernel_version(kernel)} #{kernel_size} bytes initrd: #{initrd_size} bytes"

          # call autoyast here
          execute_autoyast(:kernel => kernel, :initrd => initrd, :append => "install=#{@repo_uri}")
        end
      end
    end

    # Boostraps a machine from a bootable ISO image
    class MethodIso

      attr_reader :vm

      include MethodAutoYaST

      def initialize(vm, iso)
        @vm = vm
        @iso = iso
      end

      def execute
        Dir.mktmpdir do |dir|
          kernel = File.join(dir, 'linux')
          File.open(kernel, 'w') do |stdout|
            Cheetah.run('isoinfo', '-R', '-i', @iso, '-x', "/boot/x86_64/loader/linux", :stdout => stdout)
          end

          initrd = File.join(dir, 'initrd')
          File.open(initrd, 'w') do |stdout|
            Cheetah.run('isoinfo', '-R', '-i', @iso, '-x', "/boot/x86_64/loader/initrd", :stdout => stdout)
          end

          kernel_size = File.size?(kernel)
          initrd_size = File.size?(initrd)

          if ! (kernel_size && initrd_size)
            Vmit.logger.error "Can't download kernel & initrd"
            return 1
          end

          # , :append => "install=#{@repo_uri}"
          execute_autoyast(:append => 'install=cdrom', :cdrom => @iso, :kernel => kernel, :initrd => initrd)
        end
      end
    end

  end
end

module Vmit
  module Plugins

    # Bootstrap allows to initialize a virtual machine
    # from (currently) a (SUSE) repository.
    #
    # It will perform an autoinstallation based on
    # the repository.
    #
    class Bootstrap < ::Clamp::Command

      option ["-s","--disk-size"], "SIZE",
        "Initialize disk with SIZE (eg: 10M, 10G, 10K)" do |disk_size|
        if not disk_size =~ /(\d)+(M|K|G)/
          raise ArgumentError, "Disk size should be given as 1M, 2G, etc"
        end
        disk_size
      end

      parameter "REPOSITORY", "Repository URL to bootstrap from"

      def execute
        Vmit.logger.info 'Starting bootstrap'
        curr_dir = File.expand_path(Dir.pwd)
        vm = Vmit::VirtualMachine.new(curr_dir)

        Vmit.logger.info '  Deleting old images'
        FileUtils.rm_f(Dir.glob('*.qcow2'))
        opts = {}
        opts[:disk_size] = disk_size if disk_size
        vm.disk_image_init!(opts)
        vm.save_config!

        method = case File.extname(repository)
          when '.iso' then Vmit::Bootstrap::MethodIso.new(vm, repository)
          else Vmit::Bootstrap::MethodRepo.new(vm, repository)
        end
        method.execute

        Vmit.logger.info 'Creating snapshot of fresh system.'
        vm.disk_snapshot!
        Vmit.logger.info 'Bootstraping done. Call vmit run to start your system.'
      end

    end
  end
end