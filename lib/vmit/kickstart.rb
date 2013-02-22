require 'vmit'
require 'erb'

module Vmit

  class Kickstart

    attr_accessor :install

    # ks=floppy
    def initialize
    end

    def to_ks_script
      template = ERB.new <<-EOF
#version=F11
install
url --url=http://buildhost.example.local/dists/fedora/11/i386
lang en_US.UTF-8

keyboard us
network --device eth0 --bootproto dhcp

# root's password is 'password' - You might wanna change this
rootpw  --iscrypted $6$5hd0f046$1CwTHpvfA.1TpYXTevRXZnRD84uSR1RHa49FyNHJcAXcQw33zPGKcxt8xtuZVQxTqG5vrW8410AqjszPNHBbj.

text
# Reboot after installation
reboot
firewall --service=ssh
authconfig --enableshadow --passalgo=sha512
selinux --enforcing
timezone --utc America/New_York
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"
# NOTE, the following statements WILL DESTROY all partitions that Kickstart can see
# PLEASE MODIFY FOR YOUR ENVIRONMENT
clearpart --all --initlabel
part /boot --fstype ext3 --size=512 --asprimary
part swap --recommended --asprimary
part pv.100000 --size=1 --grow
volgroup vg_osdata --pesize=32768 pv.100000
logvol / --fstype ext4 --name=lv_root --vgname=vg_osdata --size=1 --grow
# END PARTITION SECTION

%packages --nobase
NetworkManager
audit
bzip2
crontabs
dhclient
logrotate
mailx
man
ntp
openssh
openssh-clients
openssh-server
pam_passwdqc
postfix
psacct
screen
sudo
tcpdump
telnet
wget
which
yum

%end
EOF

template = ERB.new <<-EOF
halt
rootpw linux
lang en_US.UTF-8
keyboard us
timezone --utc America/New_York
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"
install
<% if install.is_a?(String) %>
url --url=<%= install %>
<% else %>
<%= install %>
<% end %>
network --device eth0 --bootproto dhcp
clearpart --all
autopart
%packages --nobase
@core
@server-policy
wget
mc

%end
EOF
    template.result(binding)
    end


  end

end