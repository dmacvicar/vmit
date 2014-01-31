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
require 'nokogiri'
require 'vmit/unattended_install'
require 'vmit/vfs'

module Vmit
  class AutoYaST < UnattendedInstall
    def initialize(location)
      super(location)
      base!
    end

    def base!
      config.add_patterns! 'base'
      config.add_packages! 'zypper'
      config.add_packages! 'openssh'
    end

    # minimal installation
    # does not work with openSUSE
    def minimal!
      config.add_patterns! 'Minimal'
      config.add_packages! 'zypper'
      config.add_packages! 'openssh'
    end

    # @param [Hash] args Arguments for 1st stage
    def execute_autoinstall(vm, args)
      vm.config.push!
      begin
        vm.config.configure(args)
        media = Vmit::VFS.from(location)
        kernel_append_arg = case media
                            when Vmit::VFS::URI then "install=#{location}"
                            when Vmit::VFS::ISO then 'install=cdrom'
                            else fail ArgumentError.new("Unsupported autoinstallation: #{location}")
                            end
        vm.config.add_kernel_cmdline!(kernel_append_arg)

        if media.is_a?(Vmit::VFS::ISO)
          vm.config.cdrom = location.to_s
        end

        Dir.mktmpdir do |floppy_dir|
          FileUtils.chmod_R 0775, floppy_dir
          vm.config.floppy = floppy_dir
          # vm.config.add_kernel_cmdline!('autoyast=device://fd0/autoinst.xml')
          vm.config.add_kernel_cmdline!('autoyast=floppy')
          vm.config.reboot = false

          # WTF SLE and openSUSE have different
          # base pattern names
          # media.open('/content') do |content_file|
          #  content_file.each_line do |line|
          #    case line
          #      when /^DISTRIBUTION (.+)$/
          #        case $1
          #          when /SUSE_SLE/ then autoyast.minimal_sle!
          #          when /openSUSE/ then autoyast.minimal_opensuse!
          #        end
          #    end
          #  end
          # end

          File.write(File.join(floppy_dir, 'autoinst.xml'), to_xml)
          Vmit.logger.info 'AutoYaST: 1st stage.'
          puts vm.config.inspect
          vm.up
          vm.wait_until_shutdown! do
            vm.vnc
          end
          vm.config.pop!

          Vmit.logger.info 'AutoYaST: 2st stage.'
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

    def to_xml
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.profile('xmlns' => 'http://www.suse.com/1.0/yast2ns',
                    'xmlns:config' => 'http://www.suse.com/1.0/configns') do
          xml.users('config:type' => 'list') do
            xml.user do
              xml.username 'root'
              xml.user_password 'linux'
              xml.encrypted(false, 'config:type' => 'boolean')
              xml.forename
              xml.surname
            end
          end
          xml.general do
            xml.mode do
              xml.confirm(false, 'config:type' => 'boolean')
              xml.forceboot('config:type' => 'boolean')
              xml.final_reboot(true, 'config:type' => 'boolean')
              xml.second_stage(true, 'config:type' => 'boolean')
            end
          end
          xml.runlevel do
            xml.default 3
            xml.services do
              xml.service do
                xml.service_name 'sshd'
                xml.service_status 'enable'
                xml.service_start '3 5'
                xml.service_stop '3 5'
              end
            end
          end
          xml.software do
            xml.patterns('config:type' => 'list') do
              config.patterns.each do |pat|
                xml.pattern pat
              end
            end
            xml.packages('config:type' => 'list') do
              config.packages.each do |pkg|
                xml.package pkg
              end
            end
          end
          # SLE 11 can do without this basic partitioning but
          # SLE 10 is not that smart.
          xml.partitioning('config:type' => 'list') do
            xml.drive do
              xml.use 'all'
            end
          end
          xml.networking do
            xml.keep_install_network(true, 'config:type' => 'boolean')
          end
        end
      end
      builder.to_xml
    end
  end
end
