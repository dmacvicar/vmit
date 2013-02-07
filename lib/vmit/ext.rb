
module Vmit
  module Ext

    module Hash
      def symbolize_keys
        Hash[map{|(k,v)| [k.to_sym,v]}]
      end

      def symbolize_keys!
        replace(symbolize_keys)
      end
    end

  end
end

Hash.send(:include, Vmit::Ext::Hash)
