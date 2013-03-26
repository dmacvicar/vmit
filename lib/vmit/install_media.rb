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
require 'vmit/utils'
require 'vmit/vfs'
require 'confstruct'

module Vmit

  class InstallMedia
    abstract_method :unattended_install_class
    abstract_method :kernel_path
    abstract_method :initrd_path

    attr_reader :location

    def initialize(location)
      @location = location
    end

    def to_s
      "#{super.to_s}:#{location}"
    end

    def unattended_install
      unless @unattended_install
        @unattended_install = unattended_install_class.new(location)
      end
      @unattended_install
    end

    def self.class_for_media_type(type)
      case type.to_s.downcase
        when /fedora|redhat|centos/ then FedoraInstallMedia
        when /suse/ then SUSEInstallMedia
        when /debian/ then DebianInstallMedia
        else
          raise "Don't know how to bootstrap media #{location}"
      end
    end

    # @return [InstallMedia] scans the install media
    #   and returns a specific type (suse, debian, etc...)
    def self.scan(location)
      data_file = File.expand_path('install_media.yml', File.dirname(__FILE__))
      distros = YAML.load(File.read(data_file))
      distros.each do |key, data|
        next if not data['type']
        klass = class_for_media_type(data['type'])
        if data.has_key?('regexp')
          regexp = Regexp.new(data['regexp'])
          replaced_location = location.to_s
            .downcase.gsub(/[\s_]+/, '')
          match = regexp.match(replaced_location)
          next unless match
          replaced_uri = replaced_location
            .gsub(regexp, data['url'])
            .gsub('$arch', Vmit::Utils.arch)
          return klass.new(replaced_uri) if match

        end
      end
      raise ArgumentError.new("Unknown install media '#{location}'")
    end

    def autoinstall(vm)
      media = Vmit::VFS.from(location)
      kernel = media.open(kernel_path)
      initrd = media.open(initrd_path)
      opts = {:kernel => kernel.path, :initrd => initrd.path}
      unattended_install.execute_autoinstall(vm, opts)
    end

  end

  class SUSEInstallMedia < InstallMedia

    def unattended_install_class
      Vmit::AutoYaST
    end

    def initrd_path
      "/boot/#{Vmit::Utils.arch}/loader/initrd"
    end

    def kernel_path
      "/boot/#{Vmit::Utils.arch}/loader/linux"
    end
  end

  class FedoraInstallMedia < InstallMedia

    def unattended_install_class
      Vmit::Kickstart
    end

    def initrd_path
      '/images/pxeboot/initrd.img'
    end

    def kernel_path
      '/images/pxeboot/vmlinuz'
    end
  end

  class DebianInstallMedia < InstallMedia

    def unattended_install_class
      Vmit::DebianPreseed
    end

    def initrd_path
      arch = Vmit::Utils.arch.gsub(/x86_64/, 'amd64')
      "/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/initrd.gz"
    end

    def kernel_path
      arch = Vmit::Utils.arch.gsub(/x86_64/, 'amd64')
      "/main/installer-#{arch}/current/images/netboot/debian-installer/#{arch}/linux"
    end
  end

end