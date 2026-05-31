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

  describe "schema" do
    it "does not appear in db/schema.rb" do
      schema_content = Rails.root.join("db/schema.rb").read
      expect(schema_content).not_to include('create_table "payments"')
    end
  end
end
