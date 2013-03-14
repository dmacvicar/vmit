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
cmdline
halt
rootpw linux
lang en_US.UTF-8
keyboard us
timezone --utc America/New_York
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"
install
<% if install.is_a?(String) || install.is_a?(::URI)%>
url --url=<%= install.to_s.strip %>
<% else %>
<%= install %>
<% end %>
network --device eth0 --bootproto dhcp
zerombr yes
clearpart --all --initlabel
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