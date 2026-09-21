# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::AddBlocklistEntry, type: :service do
  let(:author) { create(:user, :psp_admin) }
  let(:entry)  { DomainBlocklistEntry.new }

  def call(name)
    described_class.call(entry: entry, name: name, author: author)
  end

  it "adds a domain and records who added it" do
    expect(call("godaddy.com")).to be(true)

    expect(entry).to be_persisted
    expect(entry.name).to eq("godaddy.com")
    expect(entry.created_by).to eq(author)
  end

  it "reduces a pasted URL or www. host to the registrable domain" do
    expect(call("https://www.GoDaddy.com/domains?x=1")).to be(true)

    expect(entry.name).to eq("godaddy.com")
  end

  it "handles a multi-label public suffix" do
    expect(call("www.registrar.co.uk")).to be(true)

    expect(entry.name).to eq("registrar.co.uk")
  end

  [ "", "   ", "not a domain", "mail.godaddy.com", "info@godaddy.com", "192.168.0.1", "com" ].each do |input|
    it "refuses #{input.inspect}: nothing is added and the reason is on name" do
      expect { expect(call(input)).to be(false) }.not_to change(DomainBlocklistEntry, :count)

      expect(entry.errors[:name]).to be_present
    end
  end

  it "refuses a domain that is already listed" do
    create(:domain_blocklist_entry, name: "godaddy.com")

    expect { expect(call("GoDaddy.com")).to be(false) }.not_to change(DomainBlocklistEntry, :count)

    expect(entry.errors[:name]).to be_present
  end

  it "keeps what was typed so the form can be shown again" do
    call("mail.godaddy.com")

    expect(entry.name).to eq("mail.godaddy.com")
  end

  it "does not change domains applicants already have" do
    existing = create(:applicant_domain, name: "godaddy.com", review_status: :pending)

    call("godaddy.com")

    expect(existing.reload).to be_pending
  end
end
