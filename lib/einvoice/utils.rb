require "gyoku"

module Einvoice
  module Utils
    def camelize(hash)
      hash.deep_transform_keys { |k| k.to_s.camelize }
    end

    def encode_xml(hash)
      ::Gyoku.xml(hash, key_converter: :none)
    end
  end
end
