require 'clamp'
require 'net/http'
require 'tmpdir'

module Vmit
  module Plugins
    class BootstrapPlugin < ::Clamp::Command

      def download_file(uri, target)
        cmdline = "wget -O #{target} #{uri}"
        Vmit.logger.info cmdline
        `#{cmdline}`
        return
        Net::HTTP.start(uri.host) do |http|
          begin
            file = open(target, 'wb')
            http.request_get(uri.path) do |response|
              response.read_body do |segment|
              file.write(segment)
              end
            end
          ensure
            file.close
          end
        end
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

          Vmit.logger.info "kernel: #{kernel_size} bytes initrd: #{initrd_size} bytes"

          FileUtils.rm_f "base.qcow2"
          opts = {}
          opts[:disk_size] = disk_size if disk_size
          vm.disk_image_init!(opts)

          vm.run(:kernel => kernel, :initrd => initrd,
            :append => "install=#{repo_uri} autoyast=device://fd0/autoinst.xml")
          #, '-fda', "fat:floppy:#{Dir.pwd}/floppy
        end
      end

    end
  end
end