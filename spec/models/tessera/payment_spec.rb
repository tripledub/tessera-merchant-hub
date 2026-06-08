# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::Payment, type: :model do
  subject(:payment) { build(:tessera_payment) }

  describe "table" do
    it "uses the payments table" do
      expect(described_class.table_name).to eq("payments")
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:audit_events).class_name("Tessera::AuditEvent").with_foreign_key(:payment_id) }
    it { is_expected.to have_many(:webhook_deliveries).class_name("Tessera::WebhookDelivery").with_foreign_key(:payment_id) }
  end

  describe "read-only behaviour" do
    let(:persisted_payment) { create(:tessera_payment) }

    it "raises ActiveRecord::ReadOnlyRecord on save" do
      expect { persisted_payment.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy" do
      expect { persisted_payment.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe ".for_shop" do
    let(:shop_a) { "shop_aaa" }
    let(:shop_b) { "shop_bbb" }

    before do
      create(:tessera_payment, shop_id: shop_a)
      create(:tessera_payment, shop_id: shop_a)
      create(:tessera_payment, shop_id: shop_b)
    end

    it "returns only payments for the given shop" do
      results = described_class.for_shop(shop_a)
      expect(results.count).to eq(2)
      expect(results.map(&:shop_id)).to all(eq(shop_a))
    end

    it "returns no results for an unknown shop" do
      expect(described_class.for_shop("no_such_shop")).to be_empty
    end
  end

  describe ".with_statuses" do
    before do
      create(:tessera_payment, status: "succeeded")
      create(:tessera_payment, status: "failed")
      create(:tessera_payment, status: "pending")
    end

    it "returns payments matching a single status string" do
      expect(described_class.with_statuses("succeeded").map(&:status)).to all(eq("succeeded"))
    end

    it "returns payments matching any status in an array" do
      results = described_class.with_statuses(%w[succeeded failed])
      expect(results.map(&:status).uniq).to contain_exactly("succeeded", "failed")
    end

    it "returns no results for an empty array" do
      expect(described_class.with_statuses([])).to be_empty
    end
  end

  describe ".from_date / .to_date" do
    let!(:old_payment) { create(:tessera_payment, inserted_at: 10.days.ago, updated_at: 10.days.ago) }
    let!(:recent)      { create(:tessera_payment, inserted_at: 1.day.ago,   updated_at: 1.day.ago) }
    let!(:today)       { create(:tessera_payment, inserted_at: Time.current, updated_at: Time.current) }

    it ".from_date excludes payments before the date" do
      results = described_class.from_date(2.days.ago.to_date.to_s)
      expect(results).to include(recent, today)
      expect(results).not_to include(old_payment)
    end

    it ".to_date excludes payments after the date" do
      results = described_class.to_date(5.days.ago.to_date.to_s)
      expect(results).to include(old_payment)
      expect(results).not_to include(recent, today)
    end
  end

  describe ".with_reference" do
    before do
      create(:tessera_payment, merchant_reference: "ORDER-001")
      create(:tessera_payment, merchant_reference: "ORDER-002")
      create(:tessera_payment, merchant_reference: "TXREF-999")
    end

    it "returns payments whose merchant_reference contains the query (case-insensitive)" do
      results = described_class.with_reference("order")
      expect(results.count).to eq(2)
      expect(results.map(&:merchant_reference)).to all(match(/ORDER/i))
    end

    it "returns no results when no merchant_reference matches" do
      expect(described_class.with_reference("zzz_no_match")).to be_empty
    end
  end

  describe ".amount_at_least / .amount_at_most" do
    before do
      create(:tessera_payment, amount: 500)    # £5.00
      create(:tessera_payment, amount: 1000)   # £10.00
      create(:tessera_payment, amount: 5000)   # £50.00
    end

    it ".amount_at_least returns payments at or above threshold" do
      results = described_class.amount_at_least(1000)
      expect(results.map(&:amount)).to all(be >= 1000)
    end

    it ".amount_at_most returns payments at or below threshold" do
      results = described_class.amount_at_most(1000)
      expect(results.map(&:amount)).to all(be <= 1000)
    end
  end

  describe "schema" do
    it "does not appear in db/schema.rb" do
      schema_content = Rails.root.join("db/schema.rb").read
      expect(schema_content).not_to include('create_table "payments"')
    end
  end
end
