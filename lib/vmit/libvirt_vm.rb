require 'libvirt'
require 'nokogiri'
require 'vmit'

module Vmit

  class LibvirtVM

    attr_reader :workspace
    attr_reader :conn

    def self.from_pwd(opts={})
      workspace = Vmit::Workspace.from_pwd
      LibvirtVM.new(workspace, opts)
    end

    # @param [Vmit::Workspace] workspace to run
    # @param [Hash] runtime options that override
    #   the virtual machine options
    def initialize(workspace, opts={})
      @workspace = workspace
      @runtime_opts = {}
      @runtime_opts.merge!(opts)

      @conn = ::Libvirt::open("qemu:///system")
      if not @conn
        raise 'Can\'t initialize hypervisor'
      end
    end

    # @return [Libvirt::Domain] returns the libvirt domain
    #   or creates one for the workspace if it does not exist
    def domain
      conn.lookup_domain_by_name(workspace.name) rescue nil
    end

    def up
      Vmit.logger.debug "\n#{conn.capabilities}"
      Vmit.logger.info "Starting VM..."

      network = conn.lookup_network_by_name('default')
      Vmit.logger.debug "\n#{network.xml_desc}"
      if not network.active?
        network.create
      end
      Vmit.logger.debug "\n#{self.to_libvirt_xml}"

      unless down?
        Vmit.logger.error "#{workspace.name} is already up. Run 'vmit ssh' or 'vmit vnc' to access it."
        return
      end

      if domain.nil?
        conn.create_domain_xml(self.to_libvirt_xml)
      end

      domain.resume
    end

    def state
      assert_up
      st, reason = domain.state
      st_sym = case st
        when Libvirt::Domain::NOSTATE then :unknown
        when Libvirt::Domain::RUNNING then :running
        when Libvirt::Domain::BLOCKED then :blocked
        when Libvirt::Domain::PAUSED then :paused
        when Libvirt::Domain::SHUTDOWN then :shutdown
        when Libvirt::Domain::SHUTOFF then :shutoff
        when Libvirt::Domain::CRASHED then :crashed
        when Libvirt::Domain::PMSUSPENDED then :pmsuspended
      end
      return st_sym, reason
    end

    def up?
      !domain.nil? && domain.active?
    end

    def assert_up
      unless up?
        raise "VM is not running. Try 'vmit up'..."
      end
    end

    def assert_down
      if up?
        raise "VM is running. Try 'vmit down'..."
      end
    end

    def down?
      !up?
    end

    def reboot
      assert_up
      domain.reboot
    end

    def shutdown
      assert_up
      domain.shutdown
    end

    def destroy
       if domain
        domain.destroy
        domain.free
      end
    end

    def ip_address
      File.open('/var/lib/libvirt/dnsmasq/default.leases') do |f|
        f.each_line do |line|
          parts = line.split(' ')
          if parts[1] == self[:mac_address]
            return parts[2]
          end
        end
      end
      nil
    end

    def vnc_address
      assert_up
      doc = Nokogiri::XML(domain.xml_desc)
      port = doc.xpath("//graphics[@type='vnc']/@port")
      listen = doc.xpath("//graphics[@type='vnc']/listen[@type='address']/@address")
      "#{listen}:#{port}"
    end

    # synchronus vnc viewer
    def vnc
      assert_up
      addr = vnc_address
      raise "Can't get the VNC information from the VM" unless addr
      system("vncviewer #{addr}")
    end

    def [](key)
      if @runtime_opts.has_key?(key)
        @runtime_opts[key]
      else
        workspace[key]
      end
    end

    def to_libvirt_xml
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.domain(:type => 'kvm') {
          xml.name workspace.name
          xml.uuid self[:uuid]
          match = /([0-9+])([^0-9+])/.match self[:memory]
          xml.memory(match[1], :unit => match[2])
          xml.vcpu 1
          xml.os {
            xml.type('hvm', :arch => 'x86_64')
            if self[:kernel]
              xml.kernel self[:kernel]
              xml.cmdline self[:append] if self[:append]
            end
            xml.initrd self[:initrd] if self[:initrd]
            xml.boot(:dev => 'cdrom') if self[:cdrom]
          }
          # for shutdown to work
          xml.features {
            xml.acpi
          }
          #xml.on_poweroff 'destroy'
          if not self[:reboot]
            xml.on_reboot 'destroy'
          end
          #xml.on_crash 'destroy'
          #xml.on_lockfailure 'poweroff'

          xml.devices {
            xml.emulator '/usr/bin/qemu-kvm'
            xml.disk(:type => 'file', :device => 'disk') {
              xml.driver(:name => 'qemu', :type => 'qcow2')
              xml.source(:file => workspace.current_image)
              xml.target(:dev => 'sda', :bus => 'virtio')
            }
            if self[:cdrom]
              xml.disk(:type => 'file', :device => 'cdrom') {
                xml.source(:file => self[:cdrom])
                xml.target(:dev => 'hdc')
                xml.readonly
              }
            end
            if self[:floppy]
              xml.disk(:type => 'dir', :device => 'floppy') {
                xml.source(:dir => self[:floppy])
                xml.target(:dev => 'fda')
                xml.readonly
              }
            end
            xml.graphics(:type => 'vnc', :autoport => 'yes')
            xml.interface(:type => 'network') {
              xml.source(:network => 'default')
              xml.mac(:address => self[:mac_address])
            }
          }
        }
      end
      builder.to_xml
    end

  end
end