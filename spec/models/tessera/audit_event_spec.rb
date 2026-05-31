# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tessera::AuditEvent, type: :model do
  subject(:audit_event) { build(:tessera_audit_event) }

  describe "table" do
    it "uses the audit_events table" do
      expect(described_class.table_name).to eq("audit_events")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:payment).class_name("Tessera::Payment").with_foreign_key(:payment_id) }
  end

  describe "read-only behaviour" do
    let(:persisted_event) { create(:tessera_audit_event) }

    it "raises ActiveRecord::ReadOnlyRecord on save" do
      expect { persisted_event.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy" do
      expect { persisted_event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe ".chronological" do
    let(:payment) { create(:tessera_payment) }

    before do
      create(:tessera_audit_event, payment: payment, occurred_at: 3.hours.ago)
      create(:tessera_audit_event, payment: payment, occurred_at: 1.hour.ago)
      create(:tessera_audit_event, payment: payment, occurred_at: 2.hours.ago)
    end

    it "orders events by occurred_at ascending" do
      times = described_class.chronological.map(&:occurred_at)
      expect(times).to eq(times.sort)
    end
  end

  describe "schema" do
    it "does not appear in db/schema.rb" do
      schema_content = Rails.root.join("db/schema.rb").read
      expect(schema_content).not_to include('create_table "audit_events"')
    end
  end
end
