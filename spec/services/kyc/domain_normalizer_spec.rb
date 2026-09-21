# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DomainNormalizer do
  describe ".call" do
    {
      "example.com" => "example.com",
      "  Example.COM  " => "example.com",
      "https://example.com" => "example.com",
      "https://www.example.com/path/page?q=1#top" => "example.com",
      "example.com:8443" => "example.com",
      "example.com." => "example.com",
      "www.example.com" => "example.com",
      "example.co.uk" => "example.co.uk",
      "www.example.co.uk" => "example.co.uk"
    }.each do |raw, expected|
      it "normalises #{raw.inspect} to #{expected.inspect}" do
        expect(described_class.call(raw)).to eq(expected)
      end
    end

    context "when the hostname carries a subdomain other than www" do
      it "discards it, since nobody buys a subdomain" do
        expect(described_class.call("mail.example.com")).to be_nil
        expect(described_class.call("shop.example.co.uk")).to be_nil
        expect(described_class.call("https://ns1.example.com/dns")).to be_nil
      end

      it "discards it even behind a www prefix" do
        expect(described_class.call("www.mail.example.com")).to be_nil
      end
    end

    context "when the value is not a registrable domain" do
      [
        nil,
        "",
        "   ",
        "example",
        "com",
        "co.uk",
        "not a domain",
        "info@example.com",
        "192.168.0.1",
        "example.notarealtld",
        42
      ].each do |raw|
        it "returns nil for #{raw.inspect}" do
          expect(described_class.call(raw)).to be_nil
        end
      end
    end
  end
end
