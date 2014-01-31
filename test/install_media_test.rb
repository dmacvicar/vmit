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
require 'vmit/install_media'
require 'tmpdir'

class InstallMedia_test < Test::Unit::TestCase
  def test_scan
    ['openSUSE 12.1', 'opensuse12.1', 'opensuse_12.1'].each do |key|
      media = Vmit::InstallMedia.scan(key)
      assert_kind_of(Vmit::SUSEInstallMedia, media)
      assert_equal('http://download.opensuse.org/distribution/12.1/repo/oss/',
                   media.location)
    end

    ['openSUSE Factory', 'factory', 'opensuse_factory'].each do |key|
      media = Vmit::InstallMedia.scan(key)
      assert_kind_of(Vmit::SUSEInstallMedia, media)
      assert_equal('http://download.opensuse.org/factory/repo/oss/',
                   media.location)
    end

    ['debian wheezy', 'Debian wheezy', 'debian wheezy'].each do |key|
      media = Vmit::InstallMedia.scan(key)
      assert_kind_of(Vmit::DebianInstallMedia, media)
      assert_equal('http://cdn.debian.net/debian/dists/wheezy',
                   media.location)
    end

    ['sles10sp1', 'sles-10sp1', 'SLES10 SP1', 'SLE10 SP1'].each do |key|
      media = Vmit::InstallMedia.scan(key)
      assert_kind_of(Vmit::SUSEInstallMedia, media)
      assert_equal("http://schnell.suse.de/BY_PRODUCT/sle-server-10-sp1-#{Vmit::Utils.arch}/",
                   media.location)
    end

    ['sles11', 'sles-11', 'SLES11', 'SLE11'].each do |key|
      media = Vmit::InstallMedia.scan(key)
      assert_kind_of(Vmit::SUSEInstallMedia, media)
      assert_equal("http://schnell.suse.de/BY_PRODUCT/sle-server-11-sp0-#{Vmit::Utils.arch}/",
                   media.location)
    end
  end
end