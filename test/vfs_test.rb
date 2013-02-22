require File.join(File.dirname(__FILE__), "helper")
require 'test/unit'
require 'webmock/test_unit'
require 'vmit/vfs'

class VFS_test < Test::Unit::TestCase

  def test_http_media
    stub_request(:get, 'www.server.com/foo/file').to_return(:body => 'Test response', :status => 200)

    http = Vmit::VFS::URI.from('http://www.server.com')
    http.open('/foo/file') do |f|
      assert_equal 'Test response', f .read
    end
  end

  def test_http_media_404
    stub_request(:get, 'www.server.com/lala.php').to_return(:status => [400, 'Not Found'])

    http = Vmit::VFS::URI.from('http://www.server.com')
    assert_raise OpenURI::HTTPError do
      http.open('/lala.php')
    end
  end

  def test_http_invalid_host
    stub_request(:get, 'www.unknown.com').to_raise(SocketError)
    http = Vmit::VFS::URI.from('http://www.unknown.com')
    assert_raise SocketError do
      http.open('/')
    end
  end

  def test_http_without_base_uri
    stub_request(:get, 'www.server.com/foo/file').to_return(:body => 'Test response', :status => 200)

    Vmit::VFS::URI.open('http://www.server.com/foo/file') do |f|
      assert_equal 'Test response', f .read
    end

    assert_raise ArgumentError do
      Vmit::VFS::URI.open('/foo/file')
    end
  end

  def test_media_iso
    iso_path = File.expand_path('data/test_vfs.iso', File.dirname(__FILE__))
    iso = Vmit::VFS::ISO.from("iso://#{iso_path}")

    iso.open('/dir1/file.txt') do |f|
      assert_equal "This is the content\n\n", f.read
    end
    assert_raise Errno::ENOENT do
      iso.open('/dir2/lala.txt')
    end
  end

  def test_iso_uri
    iso_path = File.expand_path('data/test_vfs.iso', File.dirname(__FILE__))
    path = '/dir1/file.txt'
    Vmit::VFS::ISO.open("iso://#{iso_path}?path=#{path}") do |f|
      assert_equal "This is the content\n\n", f.read
    end
  end
end