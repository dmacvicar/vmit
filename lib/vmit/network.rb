require 'vmit/refcounted_resource'
require 'cheetah'

module Vmit

  class Network < RefcountedResource

    attr_accessor :address

    def self.find(name)
      nil
    end

    def self.default
      BridgedNetwork.new('default', 'br0')
    end

  end

  class BridgedNetwork < Network

    def initialize(name, brdevice)
      super(name)
      @brdevice = brdevice
    end

    def on_up
      # setup bridge
      # may be use 'ip', 'link', 'show', 'dev', devname to check if
      # the bridge is there?
      Cheetah.run '/sbin/brctl', 'addbr', @brdevice
      File.write("/proc/sys/net/ipv6/conf/#{@brdevice}/disable_ipv6", 1)
      File.write('/proc/sys/net/ipv4/ip_forward', 1)
      Cheetah.run '/sbin/brctl', 'stp', @brdevice, 'on'
      Cheetah.run '/sbin/brctl', 'setfd', @brdevice, '0' rescue nil
      # setup network and dhcp on bridge
      Cheetah.run '/sbin/ifconfig', @brdevice, '192.168.58.1'
      Cheetah.run '/sbin/ifconfig', @brdevice, 'up'
      Cheetah.run 'iptables', '-t', 'nat', '-A', 'POSTROUTING', '-s', '192.168.58.254/24',
        '!', '-d', '192.168.58.254/24', '-j', 'MASQUERADE'
      @dnsmasq = IO.popen(%w(dnsmasq -Z --strict-order --bind-interfaces --listen-address 192.168.58.1 --dhcp-range 192.168.58.2,192.168.58.254))
      Vmit.logger.info "dnsmasq spawned with pid #{@dnsmasq.pid}"
    end

    def connect_interface(device)
      Vmit.logger.info "    Connecting #{device} --> #{@brdevice}"
      #Vmit::Utils.run_command(*['ovs-vsctl', 'add-port', SWITCH, ARGV[0]])
      Cheetah.run '/sbin/brctl', 'addif', @brdevice, device
    end

    def on_down
      Cheetah.run '/sbin/ifconfig', @brdevice, 'down'
      Cheetah.run '/sbin/brctl', 'delbr', @brdevice
      Cheetah.run 'iptables', '-t', 'nat', '-D', 'POSTROUTING', '-s', '192.168.58.254/24',
        '!', '-d', '192.168.58.254/24', '-j', 'MASQUERADE'
      Vmit.logger.info "Killing dnsmasq #{@dnsmasq.pid}"
      Process.kill 'SIGTERM', @dnsmasq.pid
    end

    def disconnect_interface(device)
      Vmit.logger.info "    Disconnecting #{device} -X-> #{@brdevice}"
      #Vmit::Utils.run_command(*['ovs-vsctl', 'del-port', SWITCH, ARGV[0]])
      Cheetah.run '/sbin/brctl', 'delif', @brdevice, device
    end

    def on_acquire
    end

    def on_release
    end

  end

end