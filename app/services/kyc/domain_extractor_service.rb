# frozen_string_literal: true

module Kyc
  # Asks the inference adapter which domain(s) a proof-of-domain-ownership
  # document evidences and returns them as normalised registrable domains.
  # Persisting them as ApplicantDomain rows is the caller's job.
  class DomainExtractorService
    class Error < StandardError; end

    PROMPT = <<~PROMPT
      You are a KYC document analyst. This document is proof that a business owns
      or controls one or more internet domains (for example a registrar invoice or
      receipt, a DNS or WHOIS screenshot, a hosting or domain-management letter).

      List the domain name(s) the document is evidence of ownership for.

      Return ONLY valid JSON — no explanation, no markdown fences.

      Use this exact structure:
      {
        "domains": ["example.com"]
      }

      Rules:
      - Include only the domain(s) the document evidences ownership of
      - Do NOT include the registrar, hosting provider or DNS provider's own domain
        (for example the company that issued the invoice)
      - Do NOT include nameserver hostnames, mail servers, email address domains,
        or the domains of payment or other third-party services
      - Give each domain as it is registered (for example "example.com"), without
        "https://", "www." or any path
      - Use an empty list if the document does not evidence ownership of any domain
      - Do not invent or guess domains that are not in the document
    PROMPT

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      response = Kyc::Inference.adapter.extract(document: @document, prompt: PROMPT)
      raise Error, "Expected Hash response, got #{response.class}" unless response.is_a?(Hash)

      domains = response["domains"]
      return [] if domains.nil?
      raise Error, "Expected domains list, got #{domains.class}" unless domains.is_a?(Array)

      domains.filter_map { |raw| DomainNormalizer.call(raw) }.uniq
    rescue Kyc::Inference::Error => e
      raise Error, "Inference failed: #{e.message}"
    end
  end
end
