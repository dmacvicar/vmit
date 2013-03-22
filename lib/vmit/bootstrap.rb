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
require 'vmit'
require 'vmit/autoyast'
require 'vmit/kickstart'
require 'vmit/debian_preseed'

require 'socket'

module Vmit

  module Bootstrap

    def self.arch
      Cheetah.run('arch', :stdout => :capture).strip
    end

    module MethodDebianPreseed
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        vm = Vmit::LibvirtVM.new(workspace)
        preseed = Vmit::DebianPreseed.new
        vm.config.push!
        begin
          vm.config.configure(args)
          Dir.mktmpdir do |floppy_dir|
            FileUtils.chmod_R 0755, floppy_dir
            vm.config.floppy = floppy_dir
            vm.config.add_kernel_cmdline!('preseed/file=/floppy/preseed.cfg')
            vm.config.add_kernel_cmdline!('auto=true')
            vm.config.add_kernel_cmdline!('priority=critical')
            vm.config.reboot = false

            File.write(File.join(floppy_dir, 'preseed.cfg'), preseed.to_txt)
            Vmit.logger.info "Preseed: 1st stage."
            vm.up
            vm.wait_until_shutdown! do
              vm.vnc
            end
          end
        ensure
          vm.config.pop!
        end
      end
    end

    module MethodKickstart
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        vm = Vmit::LibvirtVM.new(workspace)
        kickstart = Vmit::Kickstart.new
        vm.config.push!
        begin
          vm.config.configure(args)

          case media
            when Vmit::VFS::URI
              kickstart.install = location
            when Vmit::VFS::ISO
              kickstart.install = :cdrom
              vm.config.configure(:cdrom => location.to_s)
            else raise ArgumentError.new("Unsupported autoinstallation: #{location}")
          end

          Dir.mktmpdir do |floppy_dir|
            FileUtils.chmod_R 0755, floppy_dir
            vm.config.floppy = floppy_dir
            vm.config.add_kernel_cmdline!('ks=floppy')
            vm.config.add_kernel_cmdline!("repo=#{kickstart.install}")
            vm.config.reboot = false

            File.write(File.join(floppy_dir, 'ks.cfg'), kickstart.to_ks_script)
            Vmit.logger.info "Kickstart: 1st stage."
            vm.up
            vm.wait_until_shutdown! do
              vm.vnc
            end
          end
        ensure
          vm.config.pop!
        end
      end
    end

    module MethodAutoYaST
      # @param [Hash] args Arguments for 1st stage
      def execute_autoinstall(args)
        vm = Vmit::LibvirtVM.new(workspace)
        vm.config.push!
        begin
          vm.config.configure(args)

          kernel_append_arg = case media
            when Vmit::VFS::URI then "install=#{location}"
            when Vmit::VFS::ISO then 'install=cdrom'
            else raise ArgumentError.new("Unsupported autoinstallation: #{location}")
          end
          vm.config.add_kernel_cmdline!(kernel_append_arg)

          if media.is_a?(Vmit::VFS::ISO)
            vm.config.cdrom = location.to_s
          end

          Dir.mktmpdir do |floppy_dir|
            FileUtils.chmod_R 0755, floppy_dir
            vm.config.floppy = floppy_dir
            vm.config.add_kernel_cmdline!('autoyast=device://fd0/autoinst.xml')
            vm.config.reboot = false

            autoyast = Vmit::AutoYaST.new

            # WTF SLE and openSUSE have different
            # base pattern names
            #media.open('/content') do |content_file|
            #  content_file.each_line do |line|
            #    case line
            #      when /^DISTRIBUTION (.+)$/
            #        case $1
            #          when /SUSE_SLE/ then autoyast.minimal_sle!
            #          when /openSUSE/ then autoyast.minimal_opensuse!
            #        end
            #    end
            #  end
            #end

            File.write(File.join(floppy_dir, 'autoinst.xml'), autoyast.to_xml)
            Vmit.logger.info "AutoYaST: 1st stage."
            puts vm.config.inspect
            vm.up
            vm.wait_until_shutdown! do
              vm.vnc
            end
            vm.config.pop!

            Vmit.logger.info "AutoYaST: 2st stage."
            # 2nd stage
            vm.config.push!
            vm.config.configure(:reboot => false)
            vm.up
            vm.wait_until_shutdown! do
              vm.vnc
            end

          end
        ensure
          vm.config.pop!
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

      attr_reader :workspace
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

      def initialize(workspace, location)
        @location = location
        @workspace = workspace
        @media = Vmit::VFS.from(location)

        # TODO FIXME we need a clever way to detect the
        # location distro type. I could uname the kernel, but
        # I need the type to know the location.
        media_handler = case location.to_s.downcase
          when /fedora|redhat|centos/ then FedoraMedia
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
        raise NotImplementedError
      end
    end

  end
end