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
require 'vmit/vfs'

module Vmit

  class Kickstart < UnattendedInstall

    def initialize(location)
      super(location)

      media = Vmit::VFS.from(location)
      case media
        when Vmit::VFS::URI
          @install = location
        when Vmit::VFS::ISO
          @install = :cdrom
          vm.config.configure(:cdrom => location.to_s)
        else raise ArgumentError.new("Unsupported autoinstallation: #{location}")
      end
    end

    def execute_autoinstall(vm, args)
      vm.config.push!
      begin
        vm.config.configure(args)
        if @install == :cdrom
          vm.config.configure(:cdrom => location.to_s)
        end

        Dir.mktmpdir do |floppy_dir|
          FileUtils.chmod_R 0755, floppy_dir
          vm.config.floppy = floppy_dir
          vm.config.add_kernel_cmdline!('ks=floppy')
          vm.config.add_kernel_cmdline!("repo=#{@install}")
          vm.config.reboot = false

          File.write(File.join(floppy_dir, 'ks.cfg'), to_ks_script)
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
<% if @install.is_a?(String) || @install.is_a?(::URI)%>
url --url=<%= @install.to_s.strip %>
<% else %>
<%= @install %>
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