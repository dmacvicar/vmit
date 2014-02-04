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
require 'rubygems'
require 'progressbar'
require 'digest/sha1'

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
    dup.delete_if { |k, v| h2[k] == v }.merge!(h2.dup.delete_if { |k, v| key?(k) })
  end
end

module Vmit
  module Utils
    # @return [String] random MAC address
    def self.random_mac_address
      ('%02x' % ((rand 64).to_i * 4 | 2)) + (0..4).reduce('') { |a, e| a + ':%02x' % (rand 256).to_i }
    end

    def self.arch
      Cheetah.run('arch', :stdout => :capture).strip
    end

    # @returns [Boolean] wether the port is open
    # @note uses nmap
    def self.port_open?(host, port)
      # use logger => nil until a sane way of handling
      # non zero return codes is implemented in cheetah
      # https://github.com/openSUSE/cheetah/pull/19
      Cheetah.run(['nmap', host, '-p',
                   port.to_s, '-sV', '--version-all', '-oG', '-'],
                  ['grep', '-iq', "#{port}/open"], :logger => nil)
      true
    rescue Cheetah::ExecutionFailed
      false
    end

    # Waits unntil that host port is open
    #
    # @example
    #   Vmit::Utils.wait_for_port('192.168.0.1', 22) do
    #     # do something
    #   end
    #
    #
    def self.wait_for_port(host, port, &block)
      chars = %w{ | / - \\ }
      if block
        thread = Thread.new(&block)
        thread.abort_on_exception = true
      end

      Vmit.logger.info "Waiting for machine port #{port}..."
      loop do
        print chars[0]

        if port_open?(host, port)
          Thread.kill(thread) if thread
          break
        end
        break if thread && !thread.alive?
        sleep(1)
        print "\b"
        chars.push chars.shift
      end
      puts
    end

    def self.uname(bzimage)
      offset = 0
      File.open(bzimage) do |f|
        f.seek(0x20E)
        offset = f.read(2).unpack('s')[0]
        f.seek(offset + 0x200)
        ver = f.read(128).unpack('Z*')[0]
        return ver
      end
      nil
    end

    def self.kernel_version(bzimage)
      uname(bzimage).split(' ')[0]
    end

    def self.sha1_file(filename)
      sha1 = Digest::SHA1.new
      File.open(filename) do |file|
        buffer = ''
        # Read the file 512 bytes at a time
        until file.eof
          file.read(512, buffer)
          sha1.update(buffer)
        end
      end
      sha1.to_s
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
              if (already_dl != 0)
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
