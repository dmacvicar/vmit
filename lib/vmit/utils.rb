require 'rubygems'
require 'open4'

# Taken from Ruby on Rails
class Hash
  # Returns a hash that represents the difference between two hashes.
  #
  # Examples:
  #
  #   {1 => 2}.diff(1 => 2)         # => {}
  #   {1 => 2}.diff(1 => 3)         # => {1 => 2}
  #   {}.diff(1 => 2)               # => {1 => 2}
  #   {1 => 2, 3 => 4}.diff(1 => 2) # => {3 => 4}
  def diff(h2)
    dup.delete_if { |k, v| h2[k] == v }.merge!(h2.dup.delete_if { |k, v| has_key?(k) })
  end
end

module Vmit

  module Utils
    # @return [String] random MAC address
    def self.random_mac_address
      ("%02x"%((rand 64).to_i*4|2))+(0..4).inject(""){|s,x|s+":%02x"%(rand 256).to_i}
    end
  end

end