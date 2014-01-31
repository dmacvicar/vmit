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
require 'abstract_method'
require 'cheetah'
require 'uri'
require 'open-uri'
require 'progressbar'
require 'tempfile'

module Vmit
  module VFS
    # Opens a location
    def self.from(location, *rest, &block)
      [ISO, URI, Local].each do |handler|
        if handler.accept?(location)
          return handler.from(location)
        end
      end
      raise ArgumentError.new("#{location} not supported")
    end

    class Handler
      # alias for new
      def self.from(*args)
        self.new(*args)
      end
    end

    class URI < Handler
      # Whether this handler accepts the
      # given location
      #
      # @param uri [URI,String] location
      def self.accept?(location)
        uri = case location
              when ::URI then location
              else ::URI.parse(location.to_s)
              end
        ['http', 'ftp'].include?(uri.scheme)
      end

      # @param [String] base_url Base location
      def initialize(location)
        @base_uri = case location
                    when ::URI then location
                    else ::URI.parse(location.to_s)
                    end
      end

      def self.open(loc, *rest, &block)
        uri = case loc
              when ::URI then loc
              else ::URI.parse(loc.to_s)
              end
        unless accept?(uri)
          raise ArgumentError.new('Only HTTP/FTP supported')
        end
        @pbar = nil
        @filename = File.basename(uri.path)
        ret = OpenURI.open_uri(uri.to_s,
                               :content_length_proc => lambda do |t|
                                 if t && 0 < t
                                   @pbar = ProgressBar.new(@filename, t)
                                   @pbar.file_transfer_mode
                                 end
                               end,
                               :progress_proc => lambda do |s|
                                 @pbar.set s if @pbar
                               end, &block)
        @pbar = nil
        # So that the progress bar line get overwriten
        STDOUT.print "\r"
        STDOUT.flush
        ret
      end
      # Open a filename relative to the
      # base location.
      #
      # @param [String] loc Location to open.
      #   If a base URI was given for HTTP then
      #   the path will be relative to that
      def open(loc, *rest, &block)
        uri = @base_uri.clone
        uri.path = File.join(uri.path, loc.to_s)

        Vmit::VFS::URI.open(uri, *rest, &block)
      end
    end

    class ISO < Handler
      attr_reader :iso_file

      # Whether this handler accepts the
      # given location.
      #
      # @param uri [URI,String] location
      def self.accept?(location)
        uri = case location
              when ::URI then location
              else ::URI.parse(location)
              end

        # either an iso:// url or a local file
        unless (uri.scheme == 'iso' || uri.scheme.nil?)
          return false
        end
        return false unless File.exist?(uri.path)
        File.open(uri.path) do |f|
          f.seek(0x8001)
          return true if f.read(5) == 'CD001'
        end
        false
      end

      # Creates a ISO handler for +iso+
      # @param [URI, String] iso ISO file
      def initialize(location, *rest)
        raise ArgumentError.new(location) unless self.class.accept?(location)
        path = case location
               when ::URI then location.path
               else ::URI.parse(location).path
               end
        @iso_file = path
      end

      # Takes a iso URI on the form
      # iso:///path/tothe/file.iso?path=/file/to/get
      #
      # @param [URI, String] uri ISO file and path as query string
      def self.open(location)
        uri = case location
              when ::URI then location
              else ::URI.parse(location)
              end
        handler = self.new(uri)
        query = Hash[*uri.query.split('&').map {|p| p.split('=')}.flatten]
        unless query.has_key?("path")
          raise ArgumentError.new("#{uri}: missing path in query string")
        end
        handler.open(query["path"])
      end

      # Takes a path relative to +iso_file+
      # @see iso_file
      def open(name, *rest)
        index = Cheetah.run('isoinfo', '-f', '-R', '-i', iso_file, :stdout => :capture)
        files = index.each_line.to_a.map(&:strip)
        raise Errno::ENOENT.new(name) if not files.include?(name)
        tmp = Tempfile.new('vmit-vfs-iso-')
        Cheetah.run('isoinfo', '-R', '-i', iso_file, '-x', name, :stdout => tmp)
        tmp.close
        tmp.open
        if block_given?
          yield tmp
        end
        tmp
      end
    end

    class Local < Handler
      # Whether this handler accepts the
      # given location
      #
      # @param uri [URI,String] location
      def self.accept?(location)
        File.directory?(location.to_s)
      end

      def initialize(base_path=nil)
        @base_path = base_path
        @base_path ||= '/'
        unless File.exist?(@base_path)
          raise Errno::ENOENT.new(@base_path)
        end
      end

      def self.open(dir, *rest, &block)
        self.new(dir).open(name, *rest, &block)
      end

      def open(name, *rest, &block)
        Kernel.open(File.join(@base_path, name), *rest, &block)
      end
    end
  end
end