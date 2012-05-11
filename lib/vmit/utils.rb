require 'rubygems'
require 'open4'

# Taken from Ruby on Rails
class Hash
  # Returns a hash that represents the difference between two hashes.
  #
  # Examples:
  #
  #   {1 => 2}.diff(1 => 2)         # => {}
  #   {1 => 2}.diff(1 => 3)         # => {1 => 2}
  #   {}.diff(1 => 2)               # => {1 => 2}
  #   {1 => 2, 3 => 4}.diff(1 => 2) # => {3 => 4}
  def diff(h2)
    dup.delete_if { |k, v| h2[k] == v }.merge!(h2.dup.delete_if { |k, v| has_key?(k) })
  end
end

module Vmit

  module Utils

    DEFAULT_NETWORK = '192.168.58.0/24'

    def self.network_info
      used_bridges = []
      info = {}
      `/sbin/ip route list`.each_line do |line|
        if line =~ /^(.+) dev (br\d+)/
          network, bridge = $1, $2
          Vmit.logger.debug "  bridge #{bridge} in use"
          used_bridges << bridge if bridge =~ /^br\d+/
          
          if network == DEFAULT_NETWORK
            Vmit.logger.info "Network #{network} available on bridge #{bridge}"
            info.merge!({:bridge => bridge, :network => network})
          end
        end
      end

      next_bridge = nil
      (1..99).each do |i|
        candidate = "br#{i}"
        next if used_bridges.include?(candidate)
        info.merge!({:next_bridge => candidate})
        break
      end

      info.merge({:used_bridges => used_bridges})
    end

    def self.clean_network!
      info = network_info
      if not info.has_key?(:bridge)
        Vmit.logger.info "No network to clean"
        return
      end        

      bridge = info[:bridge]
      Vmit.logger.info "Cleaning up network setup on #{info[:bridge]}"
      run_command(*%w(kill -9 `pgrep dnsmasq|tail -1`))
      run_command(*%W(ifconfig #{bridge} down))
      run_command(*%W(ovs-vsctl del-br #{bridge}))
      run_command(*%w(iptables -t nat -D POSTROUTING -s 192.168.58.254/24 ! -d 192.168.58.254/24 -j MASQUERADE))
      Vmit.logger.info "Network on #{info[:bridge]} cleaned"
    end

    # @returns [Hash] with :bridge and :network
    #   elements for the already existing network
    #   or the one we just setup
    def self.setup_network!
      clean_network!
      info = network_info

      return info if network_info.has_key?(:bridge)

      next_bridge = info[:next_bridge]
      raise "No available bridges to setup network" if not next_bridge

      run_command('ovs-vsctl', 'add-br', next_bridge)
      run_command('echo', '1', '>', "/proc/sys/net/ipv6/conf/#{next_bridge}/disable_ipv6")
      run_command('echo', '1' '>', '/proc/sys/net/ipv4/ip_forward')
      run_command('/sbin/brctl', 'stp', next_bridge, 'on')
      run_command('/sbin/brctl', 'setfd', next_bridge, '0')
      run_command('ifconfig', next_bridge, '192.168.58.1')
      run_command('ifconfig', next_bridge, 'up')

      run_command(%w(iptables -t nat -A POSTROUTING -s 192.168.58.254/24 ! -d 192.168.58.254/24 -j MASQUERADE))
      run_command(%w(dnsmasq --strict-order --bind-interfaces --listen-address 192.168.58.1 --dhcp-range 192.168.58.2,192.168.58.254 $tftp_cmd))
      
      return {:bridge => next_bridge, :network => DEFAULT_NETWORK}
    end

    def setup_nat!(opts)
      # add iptable entry as libvirt, then guest can access public network
     #
     #/etc/init.d/dnsmasq stop
     #/etc/init.d/tftpd-hpa stop 2>/dev/null
     #dnsmasq --strict-order --bind-interfaces --listen-address 192.168.58.1 --dhcp-range 192.168.58.2,192.168.58.254 $tftp_cmd
    end

    # @return [String] random MAC address
    def self.random_mac_address
      ("%02x"%((rand 64).to_i*4|2))+(0..4).inject(""){|s,x|s+":%02x"%(rand 256).to_i}
    end

    def self.run_command(*args)
      status = Open4::popen4(*args) do|pid, stdin, stdout, stderr|
        Vmit.logger.debug "  Cmd: #{args.join(' ')}"
        Vmit.logger.debug "    Started #{args[0]} with pid #{pid}"
        stdin.close_write
        
        stderr.each_line do |line|
          Vmit.logger.debug "    #{line}"
        end

        stdout.each_line do |line|
          Vmit.logger.debug "    #{line}"
        end

      end
      raise "#{args[0]} finished with error" if status.exitstatus != 0
    end

  end

end