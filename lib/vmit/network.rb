require 'cheetah'
require 'ipaddress'
require 'yaml'

require 'vmit/refcounted_resource'

module Vmit

  class Network < RefcountedResource

    def self.create(config)
      case config
        when Hash then from_config(config)
        when String then from_alias(config)
        else raise "Can't build network from #{config}"
      end
    end

    def self.from_alias(name)
      File.open(File.join(ENV['HOME'], '.vmit', 'networks.yml')) do |f|
        # transform keys into Symbols
        networks = YAML::load(f)
        if networks.has_key?(name)
          return from_config(name, networks[name].symbolize_keys)
        else
          raise "Unknown network #{name}"
        end
      end
    end

    def self.from_config(name, config)
      BridgedNetwork.new(name, config[:address])
    end

    def self.default
      BridgedNetwork.new('default', BridgedNetwork::DEFAULT_NETWORK)
    end
  end

  # Implementation of networking with a bridge with optional
  # NAT to the host interface.
  #
  class BridgedNetwork < Network

    DEFAULT_NETWORK = '192.168.58.254/24'

    def initialize(name, address)
      super(name)

      @address = IPAddress(address).network
      brdevice = 'br0'
      @brdevice = brdevice
    end

    def to_s
      "#{@address.to_string} bridged: #{@brdevice}"
    end

    # reimplemented from RefcountedResource
    def on_up
      Vmit.logger.info "Bringing up bridged network #{@address.to_string} on #{@brdevice}"
      # setup bridge
      # may be use 'ip', 'link', 'show', 'dev', devname to check if
      # the bridge is there?
      Cheetah.run '/sbin/brctl', 'addbr', @brdevice
      File.write("/proc/sys/net/ipv6/conf/#{@brdevice}/disable_ipv6", 1)
      File.write('/proc/sys/net/ipv4/ip_forward', 1)
      Cheetah.run '/sbin/brctl', 'stp', @brdevice, 'on'
      #Cheetah.run '/sbin/brctl', 'setfd', @brdevice, '0' rescue nil
      # setup network and dhcp on bridge
      Cheetah.run '/sbin/ifconfig', @brdevice, @address.network.hosts[0].to_s
      Cheetah.run '/sbin/ifconfig', @brdevice, 'up'
      Cheetah.run 'iptables', '-t', 'nat', '-A', 'POSTROUTING', '-s', @address.network.to_string,
        '!', '-d', @address.network.to_string, '-j', 'MASQUERADE'

      start_dnsmasq
    end

    def connect_interface(device)
      Vmit.logger.info "    Connecting #{device} --> #{@brdevice}"
      #Vmit::Utils.run_command(*['ovs-vsctl', 'add-port', SWITCH, ARGV[0]])
      Cheetah.run '/sbin/brctl', 'addif', @brdevice, device
    end

    # reimplemented from RefcountedResource
    def on_down
      Cheetah.run '/sbin/ifconfig', @brdevice, 'down'
      Cheetah.run '/sbin/brctl', 'delbr', @brdevice
      Cheetah.run 'iptables', '-t', 'nat', '-D', 'POSTROUTING', '-s', @address.network.to_string,
        '!', '-d', @address.network.to_string, '-j', 'MASQUERADE'
      kill_dnsmasq
    end

    # reimplemented from RefcountedResource
    def disconnect_interface(device)
      Vmit.logger.info "    Disconnecting #{device} -X-> #{@brdevice}"
      #Vmit::Utils.run_command(*['ovs-vsctl', 'del-port', SWITCH, ARGV[0]])
      Cheetah.run '/sbin/brctl', 'delif', @brdevice, device
    end

    # reimplemented from RefcountedResource
    def on_acquire
    end

    # reimplemented from RefcountedResource
    def on_release
    end

    def start_dnsmasq
      dnsmasq_args = %W(dnsmasq -Z -x #{dnsmasq_pidfile} --strict-order --bind-interfaces --listen-address #{@address.network.hosts[0]} --dhcp-range #{@address.network.hosts[1]},#{@address.network.hosts.last})
      Vmit.logger.debug "dnsmasq arguments: '#{dnsmasq_args.join(' ')}'"
      IO.popen(dnsmasq_args)
      Vmit.logger.info "  dnsmasq spawned with pid #{dnsmasq_pid}"
    end

    def kill_dnsmasq
      Vmit.logger.info "Killing dnsmasq (#{dnsmasq_pid})"
      Process.kill('SIGTERM', dnsmasq_pid)
    end

    def dnsmasq_pid
      File.read(dnsmasq_pidfile).strip.to_i
    end

    def dnsmasq_pidfile
      File.join(lockfile_dir, 'dnsmasq.pid')
    end

  end

end