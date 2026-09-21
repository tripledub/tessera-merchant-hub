# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DomainExtractorService, type: :service do
  let(:mock_adapter) { instance_double(Kyc::Inference::Base) }
  let(:document) { create(:kyc_document, document_type: :proof_of_domain_ownership) }

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(mock_adapter)
  end

  describe ".call" do
    it "returns the normalised registrable domains the model found" do
      allow(mock_adapter).to receive(:extract).and_return(
        "domains" => [ "https://www.example.com/whois", "shop.example.co.uk", "Other-Site.NET" ]
      )

      expect(described_class.call(document)).to eq(%w[example.com other-site.net])
    end

    it "de-duplicates domains that normalise to the same value" do
      allow(mock_adapter).to receive(:extract).and_return(
        "domains" => %w[example.com www.example.com EXAMPLE.com]
      )

      expect(described_class.call(document)).to eq(%w[example.com])
    end

    it "drops entries that are not registrable domains" do
      allow(mock_adapter).to receive(:extract).and_return(
        "domains" => [ "mail.example.com", "info@example.com", "not a domain", nil, 7, "example.com" ]
      )

      expect(described_class.call(document)).to eq(%w[example.com])
    end

    it "returns an empty list when the document evidences no domains" do
      allow(mock_adapter).to receive(:extract).and_return("domains" => [])

      expect(described_class.call(document)).to eq([])
    end

    it "returns an empty list when the domains key is null or missing" do
      allow(mock_adapter).to receive(:extract).and_return({ "domains" => nil }, {})

      expect(described_class.call(document)).to eq([])
      expect(described_class.call(document)).to eq([])
    end

    it "asks for the domains the document evidences, not every hostname on it" do
      allow(mock_adapter).to receive(:extract).and_return("domains" => [])

      described_class.call(document)

      expect(mock_adapter).to have_received(:extract).with(
        document: document,
        prompt: a_string_including("\"domains\"").and(a_string_matching(/nameserver/i)).and(a_string_matching(/registrar/i))
      )
    end

    it "raises Error when the response is not a Hash" do
      allow(mock_adapter).to receive(:extract).and_return([ "example.com" ])

      expect { described_class.call(document) }
        .to raise_error(described_class::Error, /Expected Hash response/)
    end

    it "raises Error when the domains value is not a list" do
      allow(mock_adapter).to receive(:extract).and_return("domains" => "example.com")

      expect { described_class.call(document) }
        .to raise_error(described_class::Error, /Expected domains list/)
    end

    it "wraps inference failures in Error" do
      allow(mock_adapter).to receive(:extract).and_raise(Kyc::Inference::Error, "boom")

      expect { described_class.call(document) }
        .to raise_error(described_class::Error, /Inference failed: boom/)
    end
  end
end
