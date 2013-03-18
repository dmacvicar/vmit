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

module Vmit

  # Some good references here:
  # http://www.hps.com/~tpg/notebook/autoinstall.php
  class DebianPreseed

    def to_txt
      template = ERB.new <<-EOF
d-i debian-installer/locale string en_US
d-i console-tools/archs select at
d-i console-keymaps-at/keymap select American English
d-i debian-installer/keymap string us
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
d-i passwd/root-password password linux
d-i passwd/root-password-again password linux
d-i passwd/make-user boolean false
d-i grub-installer/only_debian boolean true
EOF
      return template.result(binding)
    end

  end
end