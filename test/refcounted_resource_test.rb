require File.join(File.dirname(__FILE__), "helper")
require 'test/unit'
require 'vmit/refcounted_resource'

class RefcountedResource_test < Test::Unit::TestCase

  def test_creation

    r1 = Vmit::RefcountedResource.new('test1')

    r1 = Vmit::RefcountedResource.new('test1')

  end

end