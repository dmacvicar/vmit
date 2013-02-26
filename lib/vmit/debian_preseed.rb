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
