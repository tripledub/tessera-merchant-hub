# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::WebhookDelivery, type: :model do
  subject(:webhook_delivery) { build(:tessera_webhook_delivery) }

  describe "table" do
    it "uses the webhook_deliveries table" do
      expect(described_class.table_name).to eq("webhook_deliveries")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:payment).class_name("Tessera::Payment").with_foreign_key(:payment_id) }
  end

  describe "read-only behaviour" do
    let(:persisted_delivery) { create(:tessera_webhook_delivery) }

    it "raises ActiveRecord::ReadOnlyRecord on save" do
      expect { persisted_delivery.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy" do
      expect { persisted_delivery.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "schema" do
    it "does not appear in db/schema.rb" do
      schema_content = Rails.root.join("db/schema.rb").read
      expect(schema_content).not_to include('create_table "webhook_deliveries"')
    end
  end
end
