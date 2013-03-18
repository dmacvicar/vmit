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
require 'vmit/bootstrap'
require 'tempfile'

class Bootstrap_test < Test::Unit::TestCase

  def test_accept_locations
    assert Vmit::Bootstrap::FromMedia.accept?('http://www.foof.com/repo')
    assert Vmit::Bootstrap::FromMedia.accept?(URI.parse('http://www.foof.com/repo'))
    assert Vmit::Bootstrap::FromMedia.accept?('http://www.foof.com/repo/')
    assert Vmit::Bootstrap::FromMedia.accept?(URI.parse('http://www.foof.com/repo/'))

    iso_path = File.expand_path('data/test_vfs.iso', File.dirname(__FILE__))
    tmp_raw = Tempfile.new(['vmit-test-', '.raw'])
    raw_path = tmp_raw.path

    assert Vmit::Bootstrap::FromMedia.accept?(iso_path)
    assert !Vmit::Bootstrap::FromMedia.accept?('/non/existing/file.iso')
    assert !Vmit::Bootstrap::FromMedia.accept?('/non/existing/file.raw')

    assert !Vmit::Bootstrap::FromImage.accept?(iso_path)
    assert !Vmit::Bootstrap::FromImage.accept?('/non/existing/file.iso')
    assert !Vmit::Bootstrap::FromImage.accept?('/non/existing/file.raw')

    assert !Vmit::Bootstrap::FromMedia.accept?(raw_path)
    assert Vmit::Bootstrap::FromImage.accept?(raw_path)
  end

end