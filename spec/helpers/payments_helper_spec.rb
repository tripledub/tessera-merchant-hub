# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentsHelper, type: :helper do
  describe "#filter_chip_label" do
    it "returns a status label" do
      expect(helper.filter_chip_label(:status, "succeeded")).to eq("Status: Succeeded")
    end

    it "returns a date_from label" do
      expect(helper.filter_chip_label(:date_from, "2024-01-15")).to eq("From: 2024-01-15")
    end

    it "returns a date_to label" do
      expect(helper.filter_chip_label(:date_to, "2024-01-31")).to eq("To: 2024-01-31")
    end

    it "returns a reference label" do
      expect(helper.filter_chip_label(:reference, "ORDER-001")).to eq("Ref: ORDER-001")
    end

    it "returns an amount_min label" do
      expect(helper.filter_chip_label(:amount_min, "10.50")).to eq("Min: 10.50")
    end

    it "returns an amount_max label" do
      expect(helper.filter_chip_label(:amount_max, "500")).to eq("Max: 500")
    end

    it "handles string keys" do
      expect(helper.filter_chip_label("status", "failed")).to eq("Status: Failed")
    end
  end

  describe "#filter_chip_remove_path" do
    # Simulate request.query_parameters using allow
    let(:base_params) { {} }

    before do
      allow(helper.request).to receive(:query_parameters).and_return(base_params)
    end

    context "with a scalar param" do
      let(:base_params) { { "reference" => "ORDER-001", "page" => "2" } }

      it "removes the scalar param and resets page" do
        result = helper.filter_chip_remove_path(:reference, "ORDER-001")
        expect(result).to eq(payments_path({}))
      end
    end

    context "with a multi-value status param (multiple statuses selected)" do
      let(:base_params) { { "status" => %w[succeeded failed], "page" => "3" } }

      it "removes one status value and keeps the other" do
        result = helper.filter_chip_remove_path(:status, "succeeded")
        expect(result).to eq(payments_path("status" => [ "failed" ]))
      end

      it "removes the key entirely when removing the last status" do
        base_params["status"] = [ "succeeded" ]
        result = helper.filter_chip_remove_path(:status, "succeeded")
        expect(result).to eq(payments_path({}))
      end
    end

    context "with a single-value status param (scalar)" do
      let(:base_params) { { "status" => "succeeded" } }

      it "removes the status key" do
        result = helper.filter_chip_remove_path(:status, "succeeded")
        expect(result).to eq(payments_path({}))
      end
    end

    it "always removes the page param" do
      base_params.merge!("date_from" => "2024-01-01", "page" => "5")
      result = helper.filter_chip_remove_path(:date_from, "2024-01-01")
      expect(result).not_to include("page")
    end
  end
end
