# frozen_string_literal: true

require "rails_helper"

RSpec.describe DomainBlocklistEntry, type: :model do
  subject(:entry) { build(:domain_blocklist_entry) }

  it { is_expected.to belong_to(:created_by).class_name("User").optional }
  it { is_expected.to validate_presence_of(:name) }

  it "is valid with a plain domain" do
    entry.name = "godaddy.com"
    expect(entry).to be_valid
  end

  it "rejects something that is not a domain" do
    entry.name = "not a domain"
    expect(entry).not_to be_valid
    expect(entry.errors[:name]).to be_present
  end

  it "stores the name trimmed and lowercased" do
    entry.name = "  GoDaddy.COM "
    entry.save!

    expect(entry.reload.name).to eq("godaddy.com")
  end

  it "rejects a duplicate, whatever the case" do
    create(:domain_blocklist_entry, name: "godaddy.com")
    duplicate = build(:domain_blocklist_entry, name: "GoDaddy.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to be_present
  end

  it "enforces uniqueness in the database too" do
    create(:domain_blocklist_entry, name: "godaddy.com")
    duplicate = build(:domain_blocklist_entry, name: "godaddy.com")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe ".blocks?" do
    before { create(:domain_blocklist_entry, name: "godaddy.com") }

    it "is true for a listed domain, whatever the case" do
      expect(described_class.blocks?("godaddy.com")).to be(true)
      expect(described_class.blocks?("GoDaddy.com")).to be(true)
    end

    it "is false for anything else, including look-alikes and subdomains" do
      expect(described_class.blocks?("notgodaddy.com")).to be(false)
      expect(described_class.blocks?("godaddy.com.evil.net")).to be(false)
      expect(described_class.blocks?("shop.godaddy.com")).to be(false)
      expect(described_class.blocks?("example.com")).to be(false)
    end

    it "is false for a blank or missing name" do
      expect(described_class.blocks?(nil)).to be(false)
      expect(described_class.blocks?("")).to be(false)
    end
  end
end
