# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Einvoice
  module MOF
    # 受捐贈機關或團體 as published by 財政部. A lookup result, not part of an
    # invoice — {Einvoice::Donation} is what you put on one.
    DonationCode = Data.define(:code, :name, :short_name, :ubn, :city, :raw)

    # Reads 財政部's 捐贈碼 dataset over its public ODS API — the authority for
    # whether a 愛心碼 is real, and provider-independent, so it works whatever
    # value-added center you issue through.
    #
    #   codes = Einvoice::MOF::DonationCodes.new
    #   codes.lookup("2718")   # => #<data DonationCode code="2718", name="社團法人台北市喜願協會", …>
    #   codes.exist?("105")    # => false
    #
    # Deliberately not wired into {Einvoice::Input}: validation there is local and
    # synchronous, and an issue call must never depend on a third party being up.
    # Call this when it suits you — at order time, or once at boot via {#all} to
    # build your own set, which costs five requests for the whole dataset.
    #
    # No credentials are needed today. The published OpenAPI declares +api_key+
    # and +oauth2+ schemes even though the endpoint answers anonymously, so that
    # could change; a 401/403 surfaces as {Einvoice::AuthError} saying exactly
    # that rather than as a confusing parse failure.
    class DonationCodes
      PROVIDER = "mof"
      BASE_URL = "https://dataset.einvoice.nat.gov.tw/ods/portal"
      PATH = "/api/v1/DonateCodeList"

      # 愛心碼 are 3–7 digits (MIG 捐贈碼).
      CODE_FORMAT = /\A\d{3,7}\z/
      # The API's documented ceiling; the dataset is ~2,000 rows, so a full sweep
      # is a handful of requests.
      MAX_PAGE = 500
      # Backstop so a misbehaving endpoint can't spin {#all} forever.
      MAX_PAGES = 100

      def initialize(base_url: BASE_URL, timeout: 30)
        @base_url = base_url
        @timeout = timeout
      end

      # The registered organisation for a 愛心碼, or +nil+ when the code is not in
      # the dataset. Raises {ValidationError} if it isn't 3–7 digits.
      def lookup(code)
        assert_format!(code)
        rows = get(donateCode: code)
        return nil if rows.empty?

        build(rows.first)
      end

      # Whether a 愛心碼 is registered.
      def exist?(code)
        !lookup(code).nil?
      end

      # Every code registered to a 統一編號 — an organisation may hold more than one.
      def for_ubn(ubn)
        unless ubn.to_s.match?(/\A\d{8}\z/)
          raise ValidationError.new("統一編號 must be 8 digits, got #{ubn.inspect}", provider: PROVIDER)
        end

        get(donateBan: ubn).map { |row| build(row) }
      end

      # The whole dataset, paged. Callers who want offline validation should hold
      # onto this rather than calling {#lookup} per code.
      def all
        rows = []
        MAX_PAGES.times do
          page = get(limit: MAX_PAGE, offset: rows.size)
          rows.concat(page)
          break if page.size < MAX_PAGE
        end
        rows.map { |row| build(row) }
      end

      private

      def assert_format!(code)
        return if code.to_s.match?(CODE_FORMAT)

        raise ValidationError.new("愛心碼 must be 3–7 digits, got #{code.inspect}",
                                  provider: PROVIDER)
      end

      def build(row)
        DonationCode.new(
          code: row["donateCode"].to_s,
          name: row["donateNm"].to_s,
          short_name: presence(row["donateShortNm"]),
          ubn: presence(row["donateBan"]),
          city: presence(row["hsnNm"]),
          raw: row
        )
      end

      def get(params)
        uri = URI("#{@base_url}#{PATH}")
        uri.query = URI.encode_www_form(params)
        parse(fetch(uri))
      end

      def fetch(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        response = http.request(Net::HTTP::Get.new(uri.request_uri))
        check!(response)
        response
      rescue Einvoice::Error
        raise
      rescue StandardError => e
        raise NetworkError.new("財政部 request failed: #{e.message}", provider: PROVIDER, cause: e)
      end

      # The endpoint is open today but is documented with auth schemes, so name
      # that case instead of letting it read as a malformed response.
      def check!(response)
        case response.code.to_i
        when 200 then nil
        when 401, 403
          raise AuthError.new(
            "財政部 now requires credentials for the donation-code dataset (HTTP #{response.code})",
            provider: PROVIDER, reason: Reason::CREDENTIALS_INVALID, raw_code: response.code
          )
        else
          raise ProviderError.new("財政部 returned HTTP #{response.code}", provider: PROVIDER,
                                                                        raw_code: response.code)
        end
      end

      def parse(response)
        body = JSON.parse(response.body.to_s)
        return body if body.is_a?(Array)

        raise ProviderError.new("財政部 returned an unexpected payload", provider: PROVIDER,
                                                                     raw: body)
      rescue JSON::ParserError => e
        raise ProviderError.new("財政部 returned a non-JSON response", provider: PROVIDER, cause: e)
      end

      def presence(value)
        string = value.to_s
        string.empty? ? nil : string
      end
    end
  end
end
