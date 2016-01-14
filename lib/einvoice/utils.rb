require "gyoku"

module Einvoice
  module Utils
    def serialize(object)
      object.serializable_hash(except: [:errors, :validation_context], include: [:invoice_item, :contact, :customer_defined])
    end

    def wrap(hash)
      { invoice_root:
        { invoice: hash }
      }
    end

    def camelize(hash)
      hash.deep_transform_keys { |k| k.to_s.camelize }
    end

    def encode_xml(hash)
      ::Gyoku.xml(hash, key_converter: :none)
    end
  end
end
