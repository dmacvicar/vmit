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
require 'vmit/version'
require 'vmit/unattended_install'
require 'vmit/logger'
require 'vmit/network'
require 'vmit/vfs'
require 'vmit/workspace'
require 'vmit/libvirt_vm'
require 'vmit/autoyast'
require 'vmit/kickstart'
require 'vmit/debian_preseed'
require 'vmit/install_media'
require 'vmit/ext'
require 'vmit/utils'
require 'pidfile'

module Vmit

  RUN_DIR = case Process.uid
    when 0 then '/run/vmit'
    else File.join(Dir::tmpdir, 'vmit')
  end

  module Plugins
  end
  # Your code goes here...

  def self.add_plugin(plugin)
    Vmit.plugins << plugin
  end

  def self.plugins
    @plugins ||= []
  end

  def self.load_plugins!
    # Scan plugins
    plugin_glob = File.join(File.dirname(__FILE__), 'vmit', 'plugins', '*.rb')
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
  end

end