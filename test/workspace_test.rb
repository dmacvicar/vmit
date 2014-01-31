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
require File.join(File.dirname(__FILE__), "helper")
require 'test/unit'
require 'vmit/workspace'
require 'tmpdir'

class Workspace_test < Test::Unit::TestCase
  def test_basic
    Dir.mktmpdir do |dir|
      workspace = Vmit::Workspace.new(dir)
      assert_equal '1G', workspace.config.memory
      assert !File.exist?(File.join(dir, 'config.yml'))
      assert_raises RuntimeError do
        workspace.current_image
      end

      workspace.save_config!
      assert File.exist?(File.join(dir, 'config.yml'))

      assert !File.exist?(File.join(dir, 'base.qcow2'))
      workspace.disk_image_init!
      STDERR.puts Dir.entries(dir)
      assert File.exist?(File.join(dir, 'base.qcow2'))

      assert workspace.current_image

      workspace.disk_image_shift!
      # calling this too fast screws the timestamp
      sleep(1)
      workspace.disk_image_shift!
    end
  end
end