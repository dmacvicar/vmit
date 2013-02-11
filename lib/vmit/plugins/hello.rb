require 'clamp'

module Vmit
  module Plugins
    class Hello < ::Clamp::Command

      def execute
        puts "Hello"
      end

    end
  end
end