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
require 'vmit/registry'
require 'tmpdir'

class MyTypedRegistry < Vmit::TypedRegistry
  type :key1, String
  type :key2, Fixnum
end

class Registry_test < Test::Unit::TestCase
  def test_basic_yaml
    dir = File.join(File.dirname(__FILE__), "data/registry.yml")
    reg = Vmit::YamlRegistry.new(dir)

    assert_equal '2G', reg[:memory]
    assert_equal '7a:7f:c7:dd:5f:bb', reg[:mac_address]
    assert_equal 'Hello', reg[:sym_key]
    keys = reg.keys
    assert_equal [], [:memory, :mac_address, :sym_key] - keys

    reg.each do |k, v|
      assert keys.include?(k)
      assert_equal reg[k], v
    end
  end

  def test_basic_existing_registry
    dir = File.join(File.dirname(__FILE__), "data/registry")
    reg = Vmit::FilesystemRegistry.new(dir)

    assert_equal 'val1', reg[:key1]
    assert_equal '4', reg[:key2]
    keys = reg.keys
    assert_equal [], [:key2, :key4, :key3, :key1] - keys

    reg.each do |k, v|
      assert keys.include?(k)
      assert_equal reg[k], v
    end
  end

  def test_basic_new_registry
    Dir.mktmpdir do |dir|
      reg = Vmit::FilesystemRegistry.new(dir)

      assert_nil reg[:nonexisting_key]

      reg[:hello] = "Hello"
      reg[:bye] = "Bye"

      assert_equal "Hello", reg[:hello]
      assert_equal "Bye", reg[:bye]
    end
  end

  def test_buffered
    Dir.mktmpdir do |dir|
      reg = Vmit::FilesystemRegistry.new(dir)
      breg = Vmit::BufferedRegistry.new(reg)

      reg[:hello] = "Hello"
      reg[:bye] = "Bye"

      breg[:bye] = "Bye 2"

      assert_equal "Bye", reg[:bye]
      assert_equal "Bye 2", breg[:bye]
      breg.save!
      assert_equal "Bye 2", reg[:bye]

      assert_equal "Hello", breg[:hello]
      reg[:hello] = "Hello 2"
      assert_equal "Hello", breg[:hello]
      breg.reload!
      assert_equal "Hello 2", breg[:hello]
    end
  end

  def test_typed
    Dir.mktmpdir do |dir|
      reg = Vmit::FilesystemRegistry.new(dir)
      treg = MyTypedRegistry.new(reg)

      reg[:key1] = "Hello"
      reg[:key2] = "1"

      assert_equal "Hello", treg[:key1]
      assert_equal 1, treg[:key2]

      assert_raise TypeError do
        treg[:key2] = "1"
      end
    end
  end
end
