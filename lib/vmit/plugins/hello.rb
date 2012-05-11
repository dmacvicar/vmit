require 'clamp'

module Vmit
  module Plugins
    class HelloPlugin < ::Clamp::Command

      def execute
        puts "Hello"
      end

    end
  end
end