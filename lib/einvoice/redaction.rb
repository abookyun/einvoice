# frozen_string_literal: true

require "uri"

module Einvoice
  # Keeps credentials, buyer data and plain-HTTP traffic out of places where
  # they leak: inspect output (logs, consoles, error trackers) and the network.
  module Redaction
    FILTERED = "[FILTERED]"

    # For value types with a +raw+ field. +raw+ is the provider's response, and
    # it holds the buyer's name, address, email and phone, so inspect and pp
    # show it as [FILTERED]. Read +#raw+ directly when you need it.
    module Raw
      def inspect
        fields = to_h.map { |key, value| "#{key}=#{key == :raw ? FILTERED : value.inspect}" }
        "#<data #{self.class.name} #{fields.join(', ')}>"
      end
      alias to_s inspect

      def pretty_print(printer)
        printer.text(inspect)
      end
    end

    LOCALHOST = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    module_function

    # A base URL for a provider. It has to use https. Only localhost may use
    # http, for tests. Credentials and buyer data must not go over plain HTTP.
    def base_url!(url, provider:)
      uri = URI.parse(url.to_s)
      return url if uri.scheme == "https" && !uri.host.to_s.empty?
      return url if uri.scheme == "http" && LOCALHOST.include?(uri.host)

      raise ValidationError.new("base_url must use https (http is allowed for localhost only), got #{url}",
                                provider: provider)
    rescue URI::InvalidURIError
      raise ValidationError.new("base_url is not a valid URL: #{url}", provider: provider)
    end
  end
end
