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

    class InstallMedia
      abstract_method :unattended_install_class
      abstract_method :kernel_path
      abstract_method :initrd_path

      attr_reader :location

      def initialize(location)
        @location = location
      end

      # @return [InstallMedia] scans the install media
      #   and returns a specific type (suse, debian, etc...)
      def self.scan(location)
        media_type = case location.to_s.downcase
          when /fedora|redhat|centos/ then FedoraInstallMedia
          when /suse/ then SUSEInstallMedia
          when /debian/ then DebianInstallMedia
          else
            raise "Don't know how to bootstrap media #{location}"
        end
        media_type.new(location)
      end

      def self.autoinstall_from(location)
        install_media = InstallMedia.scan(location)
        vm = LibvirtVM.from_pwd
        media = Vmit::VFS.from(location)

        kernel = media.open(install_media.kernel_path)
        initrd = media.open(install_media.initrd_path)

        unattended_install = install_media.unattended_install_class.new(location)
        opts = {:kernel => kernel.path, :initrd => initrd.path}
        unattended_install.execute_autoinstall(vm, opts)
      end

    end

    def self.arch
      Cheetah.run('arch', :stdout => :capture).strip
    end

    class SUSEInstallMedia < InstallMedia

      def unattended_install_class
        Vmit::AutoYaST
      end

      def initrd_path
        "/boot/#{Vmit::Bootstrap.arch}/loader/initrd"
      end

      def kernel_path
        "/boot/#{Vmit::Bootstrap.arch}/loader/linux"
      end
    end

    class FedoraInstallMedia < InstallMedia

      def unattended_install_class
        Vmit::Kickstart
      end

      def initrd_path
        '/images/pxeboot/initrd.img'
      end

      def initrd_path
        '/images/pxeboot/vmlinuz'
      end
    end

    class DebianInstallMedia < InstallMedia

      def unattended_install_class
        Vmit::DebianPreseed
      end

      def initrd_path
        arch = Vmit::Bootstrap.arch.gsub(/x86_64/, 'amd64')
        "/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/initrd.gz"
      end

      def kernel_path
        arch = Vmit::Bootstrap.arch.gsub(/x86_64/, 'amd64')
        "/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/linux"
      end
    end

  end
end