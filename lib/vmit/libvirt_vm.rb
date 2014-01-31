require 'confstruct'
require 'libvirt'
require 'nokogiri'
require 'vmit/workspace'

module Vmit
  class LibvirtVM
    attr_reader :workspace
    attr_reader :config
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
      @config = Confstruct::Configuration.new(@workspace.config)
      @config.configure(opts)

      @conn = ::Libvirt.open("qemu:///system")
      if not @conn
        fail 'Can\'t initialize hypervisor'
      end
    end

    # @return [Libvirt::Domain] returns the libvirt domain
    #   or creates one for the workspace if it does not exist
    def domain
      conn.lookup_domain_by_name(workspace.name) rescue nil
    end

    def up
      unless down?
        Vmit.logger.error "#{workspace.name} is already up. Run 'vmit ssh' or 'vmit vnc' to access it."
        return
      end

      Vmit.logger.debug "\n#{conn.capabilities}"
      Vmit.logger.info "Starting VM..."

      network = conn.lookup_network_by_name('default')
      Vmit.logger.debug "\n#{network.xml_desc}"
      if not network.active?
        network.create
      end
      Vmit.logger.debug "\n#{to_libvirt_xml}"

      puts domain.inspect
      domain.destroy if domain
      if domain.nil?
        conn.create_domain_xml(to_libvirt_xml)
      end
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
        fail "VM is not running. Try 'vmit up'..."
      end
    end

    def assert_down
      if up?
        fail "VM is running. Try 'vmit down'..."
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
      end
    end

    # Waits until the machine is shutdown
    # executing the passed block.
    #
    # If the machine is shutdown, the
    # block will be killed. If the block
    # exits, the machine will be stopped
    # immediately (domain destroyed)
    #
    # @example
    #   vm.wait_until_shutdown! do
    #     vm.vnc
    #   end
    #
    def wait_until_shutdown!(&block)
      chars = %w{ | / - \\ }
      thread = Thread.new(&block)
      thread.abort_on_exception = true

      Vmit.logger.info "Waiting for machine..."
      while true
        print chars[0]

        if down?
          Thread.kill(thread)
          return
        end
        if not thread.alive?
          domain.destroy
        end
        sleep(1)
        print "\b"
        chars.push chars.shift
      end
    end

    def ip_address
      File.open('/var/lib/libvirt/dnsmasq/default.leases') do |f|
        f.each_line do |line|
          parts = line.split(' ')
          if parts[1] == config.mac_address
            return parts[2]
          end
        end
      end
      nil
    end

    def spice_address
      assert_up
      doc = Nokogiri::XML(domain.xml_desc)
      port = doc.xpath("//graphics[@type='spice']/@port")
      listen = doc.xpath("//graphics[@type='spice']/listen[@type='address']/@address")
      return listen, port
    end

    def vnc_address
      assert_up
      doc = Nokogiri::XML(domain.xml_desc)
      port = doc.xpath("//graphics[@type='vnc']/@port")
      listen = doc.xpath("//graphics[@type='vnc']/listen[@type='address']/@address")
      "#{listen}:#{port}"
    end

    # synchronus spice viewer
    def spice
      assert_up
      addr, port = spice_address
      fail "Can't get the SPICE information from the VM" unless addr
      system("spicec --host #{addr} --port #{port}")
    end

    # synchronus vnc viewer
    def vnc
      assert_up
      addr = vnc_address
      fail "Can't get the VNC information from the VM" unless addr
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
        xml.domain(:type => 'kvm') do
          xml.name workspace.name
          xml.uuid config.uuid
          match = /([0-9+])([^0-9+])/.match config.memory
          xml.memory(match[1], :unit => match[2])
          xml.vcpu 1
          xml.os do
            xml.type('hvm', :arch => 'x86_64')
            if config.lookup!('kernel')
              xml.kernel config.kernel
              if config.lookup!('kernel_cmdline')
                xml.cmdline config.kernel_cmdline.join(' ')
              end
            end
            xml.initrd config.initrd if config.lookup!('initrd')
            xml.boot(:dev => 'cdrom') if config.lookup!('cdrom')
          end
          # for shutdown to work
          xml.features do
            xml.acpi
          end
          #xml.on_poweroff 'destroy'
          unless config.lookup!('reboot').nil? || config.lookup!('reboot')
            xml.on_reboot 'destroy'
          end
          #xml.on_crash 'destroy'
          #xml.on_lockfailure 'poweroff'

          xml.devices do
            xml.emulator '/usr/bin/qemu-kvm'
            xml.channel(:type => 'spicevmc') do
              xml.target(:type => 'virtio', :name => 'com.redhat.spice.0')
            end

            xml.disk(:type => 'file', :device => 'disk') do
              xml.driver(:name => 'qemu', :type => 'qcow2')
              xml.source(:file => workspace.current_image)
              if config.virtio
                xml.target(:dev => 'sda', :bus => 'virtio')
              else
                xml.target(:dev => 'sda', :bus => 'ide')
              end
            end
            if config.lookup!('cdrom')
              xml.disk(:type => 'file', :device => 'cdrom') do
                xml.source(:file => config.cdrom)
                xml.target(:dev => 'hdc')
                xml.readonly
              end
            end
            if config.lookup!('floppy')
              xml.disk(:type => 'dir', :device => 'floppy') do
                xml.source(:dir => config.floppy)
                xml.target(:dev => 'fda')
                xml.readonly
              end
            end
            xml.graphics(:type => 'vnc', :autoport => 'yes')
            xml.graphics(:type => 'spice', :autoport => 'yes')
            xml.interface(:type => 'network') do
              xml.source(:network => 'default')
              xml.mac(:address => config.mac_address)
            end
          end
        end
      end
      builder.to_xml
    end
  end
end
