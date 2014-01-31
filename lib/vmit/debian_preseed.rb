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
require 'erb'
require 'vmit/unattended_install'

module Vmit
  # Some good references here:
  # http://www.hps.com/~tpg/notebook/autoinstall.php
  class DebianPreseed < UnattendedInstall
    def execute_autoinstall(vm, args)
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

          File.write(File.join(floppy_dir, 'preseed.cfg'), to_txt)
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

    def to_txt
      template = ERB.new <<-EOF
d-i debconf/priority select critical
d-i auto-install/enabled boolean true
d-i debian-installer/locale string en_US
d-i console-tools/archs select at
d-i console-keymaps-at/keymap select American English

d-i debian-installer/keymap string us

d-i netcfg/choose_interface            select auto
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_hostname seen true
d-i netcfg/get_domain string unassigned-domain
d-i netcfg/get_domain seen true

d-i mirror/protocol string ftp
d-i mirror/ftp/hostname string ftp.de.debian.org
d-i mirror/ftp/directory string /debian/
d-i mirror/ftp/proxy string

d-i partman-auto/method string regular
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i clock-setup/utc boolean true
d-i time/zone string US/Eastern
d-i clock-setup/ntp boolean true
popularity-contest popularity-contest/participate boolean false

d-i pkgsel/include string ssh rsync initrd-tools cramfsprogs lzop

d-i passwd/root-login boolean true
d-i passwd/root-password password linux
d-i passwd/root-password-again password linux
d-i passwd/make-user boolean false
d-i grub-installer/only_debian boolean true
EOF
      return template.result(binding)
    end
  end
end
