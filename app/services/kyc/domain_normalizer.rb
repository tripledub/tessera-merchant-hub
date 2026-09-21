# frozen_string_literal: true

module Kyc
  # Reduces whatever the extraction model returned for a domain (a URL, a bare
  # hostname, "www." prefixed, etc.) to the registrable domain an applicant
  # could actually own, or nil if there isn't one.
  #
  # Hostnames with any subdomain label besides a leading "www." are discarded:
  # nobody buys "mail.example.com", so on a proof-of-domain document it points
  # at a domain that isn't the applicant's (nameserver, mail host, etc.).
  class DomainNormalizer
    SCHEME = %r{\A[a-z][a-z0-9+.-]*://}
    WWW_PREFIX = /\Awww\./
    PORT = /:\d+\z/

    def self.call(raw)
      new(raw).call
    end

    def initialize(raw)
      @raw = raw
    end

    def call
      host = extract_host
      return if host.blank?

      parsed = PublicSuffix.parse(host, default_rule: nil)
      return if parsed.trd.present?

      parsed.domain if parsed.domain.match?(ApplicantDomain::DOMAIN_FORMAT)
    rescue PublicSuffix::Error
      nil
    end

    private

    def extract_host
      return unless @raw.is_a?(String)

      value = @raw.strip.downcase
      return if value.match?(/[\s@]/)

      value.sub(SCHEME, "").split(%r{[/?#]}, 2).first.to_s
           .sub(PORT, "").chomp(".").sub(WWW_PREFIX, "")
    end
  end
end
