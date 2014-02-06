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
        fail "Don't know how to bootstrap media #{location}"
      end
    end

    # @return [InstallMedia] an install media for an arbitrary
    #   string like 'sles 11 sp2' or 'SLED-11_SP3'
    #
    # @raise [ArgumentError] if can't figure out an install media
    #   from the string
    def self.alias_to_install_media(key)
      case key.to_s.downcase.gsub(/[\s_\-]+/, '')
      when /^opensuse(\d+\.\d+)$/
        SUSEInstallMedia.new(
          'http://download.opensuse.org/distribution/$version/repo/oss/'
            .gsub('$version', $1))
      when /^(opensuse)?factory$/
        SUSEInstallMedia.new(
          'http://download.opensuse.org/factory/repo/oss/')
      when /^debian(.+)$/
        DebianInstallMedia.new(
          'http://cdn.debian.net/debian/dists/$version'
            .gsub('$version', $1))
      when /^ubuntu(.+)$/
        UbuntuInstallMedia.new(
          'http://archive.ubuntu.com/ubuntu/dists/$version'
            .gsub('$version', $1))
      when /^fedora(\d+)/
        FedoraInstallMedia.new(
          'http://mirrors.n-ix.net/fedora/linux/releases/$release/Fedora/$arch/os/'
            .gsub('$arch', Vmit::Utils.arch)
            .gsub('$release', $1))
      when /^sle(s|d)?(\d+)(sp(\d+))?$/
        edition = case $1
                  when 's' then 'sle-server'
                  when 'd' then 'sle-desktop'
                  else
                    Vmit.logger.warn 'SLE given. Assuming server.'
                    'sle-server'
                  end
        release = $2
        sp = $4 || '0'
        klass = if release.to_i > 9
          SUSEInstallMedia
        else
          SUSE9InstallMedia
        end
        suffix = if release.to_i > 9
          '/DVD1'
        else
          if sp.to_i > 0
            '/CD1'
          else
            ''
          end
        end
        klass.new(
          'http://schnell.suse.de/BY_PRODUCT/$edition-$release-sp$sp-$arch$topdir'
            .gsub('$edition', edition)
            .gsub('$arch', Vmit::Utils.arch)
            .gsub('$release', release)
            .gsub('$sp', sp)
            .gsub('$topdir', suffix))
      else fail ArgumentError.new("Unknown install media '#{key}'")
      end
    end

    # @return [InstallMedia] an install media for a url.
    #   it accesses the network in order to detect the
    #   url type.
    #
    # @raise [ArgumentError] if can't figure out an install media
    #   from the string
    def self.url_to_install_media(url)
      media = Vmit::VFS.from(url)
      media.open('/content')
      return SUSEInstallMedia.new(url)
    rescue
      raise ArgumentError.new("Don't know the install media '#{url}'")
    end

    # @return [InstallMedia] scans the install media
    #   and returns a specific type (suse, debian, etc...)
    def self.scan(key)
      case key
      when /^http:\/|ftp:\// then url_to_install_media(key)
      else alias_to_install_media(key)
      end
    end

    def autoinstall(vm)
      Vmit.logger.debug("Autoinstall from #{location}")
      media = Vmit::VFS.from(location)
      kernel = media.open(kernel_path)
      initrd = media.open(initrd_path)
      opts = { :kernel => kernel.path, :initrd => initrd.path }
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

  class SUSE9InstallMedia < SUSEInstallMedia
    def initrd_path
      '/boot/loader/initrd'
    end

    def kernel_path
      '/boot/loader/linux'
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
    def name
      'debian'
    end

    def unattended_install_class
      Vmit::DebianPreseed
    end

    def initrd_path
      arch = Vmit::Utils.arch.gsub(/x86_64/, 'amd64')
      "/main/installer-#{arch}/current/images/netboot/#{name}-installer/#{arch}/initrd.gz"
    end

    def kernel_path
      arch = Vmit::Utils.arch.gsub(/x86_64/, 'amd64')
      "/main/installer-#{arch}/current/images/netboot/#{name}-installer/#{arch}/linux"
    end
  end

  class UbuntuInstallMedia < DebianInstallMedia
    def name
      'ubuntu'
    end
  end
end
