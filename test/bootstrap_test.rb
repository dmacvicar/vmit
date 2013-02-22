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