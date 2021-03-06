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
require 'abstract_method'
require 'cheetah'
require 'ipaddress'
require 'yaml'

require 'vmit/refcounted_resource'

module Vmit
  class Network < RefcountedResource
    abstract_method :connect_interface
    abstract_method :disconnect_interface

    def resource_class
      'network'
    end

    def self.create(config)
      case config
      when Hash then from_config(config)
      when String then from_alias(config)
      else fail "Can't build network from #{config}"
      end
    end

    def self.from_alias(name)
      File.open(File.join(ENV['HOME'], '.vmit', 'networks.yml')) do |f|
        # transform keys into Symbols
        networks = YAML.load(f)
        if networks.key?(name)
          return from_config(networks[name].symbolize_keys)
        else
          fail "Unknown network #{name}"
        end
      end
    end

    def self.from_config(config)
      BridgedNetwork.new(config[:address])
    end

    def self.default
      BridgedNetwork.new(BridgedNetwork::DEFAULT_NETWORK)
    end
  end

  # Implementation of networking with a bridge with optional
  # NAT to the host interface.
  #
  class BridgedNetwork < Network
    DEFAULT_NETWORK = '192.168.58.254/24'

    def initialize(address)
      @address = IPAddress(address).network
      brdevice = 'br0'
      @brdevice = brdevice
      super("#{@brdevice}-#{@address.to_u32}")
    end

    def to_s
      "#{@brdevice}:#{@address.to_string}"
    end

    # reimplemented from RefcountedResource
    def on_up
      Vmit.logger.info "Bringing up bridged network #{@address.to_string} on #{@brdevice}"
      Vmit.logger.info "  `-> managed by #{lockfile_path}"
      # setup bridge
      # may be use 'ip', 'link', 'show', 'dev', devname to check if
      # the bridge is there?
      Cheetah.run '/sbin/brctl', 'addbr', @brdevice
      File.write("/proc/sys/net/ipv6/conf/#{@brdevice}/disable_ipv6", 1)
      File.write('/proc/sys/net/ipv4/ip_forward', 1)
      Cheetah.run '/sbin/brctl', 'stp', @brdevice, 'on'
      # Cheetah.run '/sbin/brctl', 'setfd', @brdevice, '0' rescue nil
      # setup network and dhcp on bridge
      Cheetah.run '/sbin/ifconfig', @brdevice, @address.network.hosts[0].to_s
      Cheetah.run '/sbin/ifconfig', @brdevice, 'up'
      Cheetah.run 'iptables', '-t', 'nat', '-A', 'POSTROUTING', '-s', @address.network.to_string,
                  '!', '-d', @address.network.to_string, '-j', 'MASQUERADE'

      start_dnsmasq
    end

    def connect_interface(device)
      Vmit.logger.info "    Connecting #{device} --> #{@brdevice}"
      # Vmit::Utils.run_command(*['ovs-vsctl', 'add-port', SWITCH, ARGV[0]])
      Cheetah.run '/sbin/brctl', 'addif', @brdevice, device
    end

    # reimplemented from RefcountedResource
    def on_down
      Vmit.logger.info "Bringing down bridged network #{@address.to_string} on #{@brdevice}"
      Vmit.logger.info "  `-> managed by #{lockfile_path}"
      Cheetah.run '/sbin/ifconfig', @brdevice, 'down'
      Cheetah.run '/sbin/brctl', 'delbr', @brdevice
      Cheetah.run 'iptables', '-t', 'nat', '-D', 'POSTROUTING', '-s', @address.network.to_string,
                  '!', '-d', @address.network.to_string, '-j', 'MASQUERADE'
      kill_dnsmasq
    end

    # reimplemented from RefcountedResource
    def disconnect_interface(device)
      Vmit.logger.info "    Disconnecting #{device} -X-> #{@brdevice}"
      # Vmit::Utils.run_command(*['ovs-vsctl', 'del-port', SWITCH, ARGV[0]])
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
      # Vmit.logger.info "  dnsmasq spawned with pid #{dnsmasq_pid}"
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
