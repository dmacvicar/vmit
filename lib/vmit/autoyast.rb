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

module Vmit

  class AutoYaST

    attr_accessor :patterns
    attr_accessor :packages

    def initialize
      @net_udev = {}
      @patterns = []
      @packages = []
    end

    def minimal_opensuse!
      @patterns << 'base'
    end

    def minimal_sle!
      @patterns << 'Minimal'
    end

    # Map a network device name and make
    # it persistent
    #
    # @param [String] MAC mac address
    # @param [String] device name
    def name_network_device(mac, name)
      if @net_udev.has_key?(mac) or @net_udev.has_value?(mac)
        raise "Device with MAC #{mac} is already assigned to #{@net_udev[name]}"
      end
      @net_udev[mac] = name
    end

    def to_xml
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.profile('xmlns' => 'http://www.suse.com/1.0/yast2ns',
          'xmlns:config' => 'http://www.suse.com/1.0/configns') {
          xml.users('config:type' => 'list') {
            xml.user {
              xml.username 'root'
              xml.user_password 'linux'
              xml.encrypted(false,'config:type' => 'boolean')
              xml.forename
              xml.surname
            }
          }
          xml.general {
            xml.mode {
              xml.confirm(false, 'config:type' => 'boolean')
              xml.forceboot('config:type' => 'boolean')
              xml.final_reboot(true, 'config:type' => 'boolean')
              xml.second_stage(true, 'config:type' => 'boolean')
            }
          }
          xml.runlevel {
            xml.default 3
            xml.services {
              xml.service {
                xml.service_name 'sshd'
                xml.service_status 'enable'
                xml.service_start '3 5'
                xml.service_stop '3 5'
              }
            }
          }
          xml.software {
            xml.patterns('config:type' => 'list') {
              @patterns.each do |pat|
                xml.pattern pat
              end
            }
          }
          # SLE 11 can do without this basic partitioning but
          # SLE 10 is not that smart.
          xml.partitioning('config:type' => 'list') {
            xml.drive {
              xml.use 'all'
            }
          }
          xml.networking {
            xml.keep_install_network(true, 'config:type' => 'boolean')
          }
        }
      end
      builder.to_xml
    end
  end
end