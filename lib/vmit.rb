require 'vmit/version'
require 'vmit/logger'
require 'vmit/refcounted_resource'
require 'vmit/network'
require 'vmit/virtual_machine'

module Vmit

  module Plugins
  end
  # Your code goes here...

  def self.add_plugin(plugin)
    Vmit.plugins << plugin
  end

  def self.plugins
    @plugins ||= []
  end

end

# Scan plugins
plugin_glob = File.join(File.dirname(__FILE__), 'vmit', 'plugins', '*.rb')
puts plugin_glob
Dir.glob(plugin_glob).each do |plugin|
  Vmit.logger.debug("Loading file: #{plugin}")
  #puts "Loading file: #{plugin}"
  load plugin
end

# instantiate plugins
::Vmit::Plugins.constants.each do |cnt|
  pl_class = ::Vmit::Plugins.const_get(cnt)
  #pl_instance = pl_class.new
  Vmit.add_plugin(pl_class)
  Vmit.logger.debug("Loaded: #{pl_class}")
  #puts "Loaded: #{pl_class}"
end