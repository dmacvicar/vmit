require 'vmit/autoyast'
require 'clamp'
require 'net/http'
require 'progressbar'
require 'tmpdir'


module Vmit
  module Plugins

    # Bootstrap allows to initialize a virtual machine
    # from (currently) a (SUSE) repository.
    #
    # It will perform an autoinstallation based on
    # the repository.
    #
    class Bootstrap < ::Clamp::Command

      # Utility function, may be move it
      # to Vmit::Utils in the future
      def download_file(uri, target)
        progress = ProgressBar.new(File.basename(uri.path), 100)
        Net::HTTP.start(uri.host) do |http|
          begin
            file = open(target, 'wb')
            http.request_get(uri.path) do |response|
              dl_size = response.content_length
              already_dl = 0
              response.read_body do |segment|
              already_dl += segment.length
              if(already_dl != 0)
                progress.set((already_dl * 100) / dl_size)
              end
              file.write(segment)
              end
            end
          ensure
            file.close
          end
        end
      end

      def kernel_version(bzimage)
        offset = 0
        File.open(bzimage) do |f|
          f.seek(0x20E)
          offset = f.read(2).unpack('s')[0]
          f.seek(offset + 0x200)
          ver = f.read(128).unpack('Z*')[0]
          return ver.split(' ')[0]
        end
        nil
      end

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
        repo_uri = URI.parse(repository)
        arch = 'x86_64'

        Dir.mktmpdir do |dir|
          kernel = File.join(dir, 'linux')
          initrd = File.join(dir, 'initrd')

          download_file(URI.join(repo_uri, "boot/#{arch}/loader/linux"), kernel)
          download_file(URI.join(repo_uri, "boot/#{arch}/loader/initrd"), initrd)


          kernel_size = File.size?(kernel)
          initrd_size = File.size?(initrd)

          if ! (kernel_size && initrd_size)
            Vmit.logger.error "Can't download kernel & initrd"
            return 1
          end

          Vmit.logger.info "kernel: #{kernel_version(kernel)} #{kernel_size} bytes initrd: #{initrd_size} bytes"

          FileUtils.rm_f "base.qcow2"
          opts = {}
          opts[:disk_size] = disk_size if disk_size
          vm.disk_image_init!(opts)
          vm.save_config!

          Dir.mktmpdir do |floppy_dir|
            autoyast = Vmit::AutoYaST.new
            # Configure the autoinstallation profile to persist eth0
            # for the current MAC address
            # The interface will be setup with DHCP by default.
            # TODO: make this more flexible in the future?
            #autoyast.name_network_device(vm[:mac_address], 'eth0')
            File.write(File.join(floppy_dir, 'autoinst.xml'), autoyast.to_xml)
            vm.run(:kernel => kernel, :initrd => initrd,
                  :floppy => floppy_dir,
                  :append => "install=#{repo_uri} autoyast=device://fd0/autoinst.xml",
                  :reboot => false)
            # 2nd stage
            vm.run(:reboot => false)
            Vmit.logger.info 'Creating snapshot of fresh system.'
            vm.disk_snapshot!
            Vmit.logger.info 'Bootstraping done. Call vmit run to start your system.'
          end
        end
      end

    end
  end
end