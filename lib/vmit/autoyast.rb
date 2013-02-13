require 'nokogiri'

module Vmit

  class AutoYaST

    def initialize
      @net_udev = {}
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
              xml.pattern 'Minimal'
            }
          }
          xml.networking {
            xml.keep_install_network(true, 'config:type' => 'boolean')
=begin
            @net_udev.each do |mac, devname|
              xml.send(:'net-udev', 'config:type' => 'list') {
                xml.rule 'ATTR{address}'
                xml.value mac
                xml.name devname
              }
            end
            xml.interfaces('config:type' => 'list') {
              @net_udev.each do |mac, devname|
                xml.interface {
                  xml.bootproto 'dhcp'
                  xml.device devname
                  xml.startmode 'onboot'
                }
              end
            }
=end
          }
        }
      end
      builder.to_xml
    end
  end
end