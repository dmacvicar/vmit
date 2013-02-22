require 'vmit/autoyast'
require 'vmit/kickstart'
require 'abstract_method'
require 'clamp'
require 'net/http'
require 'tmpdir'
require 'uri'
require 'vmit'

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

      parameter "LOCATION", "Repository URL or ISO image to bootstrap from"

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

        uri = URI.parse(location)
        bootstrap = [Vmit::Bootstrap::FromImage,
                  Vmit::Bootstrap::FromMedia].find do |method|
          method.accept?(uri)
        end

        if bootstrap
          bootstrap.new(vm, uri).execute
        else
          raise "Can't bootstrap from #{location}"
        end

        Vmit.logger.info 'Creating snapshot of fresh system.'
        vm.disk_snapshot!
        Vmit.logger.info 'Bootstraping done. Call vmit run to start your system.'
      end

    end
  end
end