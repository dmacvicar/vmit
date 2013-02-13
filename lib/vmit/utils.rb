require 'rubygems'
require 'open4'
require 'progressbar'

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

    def self.kernel_version(bzimage)
      offset = 0
      File.open(bzimage) do |f|
        f.seek(0x20E)
        offset = f.read(2).unpack('s')[0]
        f.seek(offset + 0x200)
        ver = f.read(128).unpack('Z*')[0]
        return ver.split(' ')[0]
      end
      nil
    end

    # @param [String] uri uri to download
    # @param [String] target where to donwload the file (directory)
    def self.download_file(uri, target)
      progress = ProgressBar.new(File.basename(uri.path), 100)
      Net::HTTP.start(uri.host) do |http|
        begin
          file = open(target, 'wb')
          http.request_get(uri.path) do |response|
            dl_size = response.content_length
            already_dl = 0
            response.read_body do |segment|
            already_dl += segment.length
            if(already_dl != 0)
              progress.set((already_dl * 100) / dl_size)
            end
            file.write(segment)
            end
          end
        ensure
          file.close
        end
      end
    end

  end
end