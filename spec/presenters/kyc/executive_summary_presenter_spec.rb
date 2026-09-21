# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ExecutiveSummaryPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }

  # MH-251: the Summary tab must agree with the Overview card for the same applicant.
  describe "#compliance_status_badge" do
    it "shows a neutral 'Not Assessable' badge when no ownership is captured" do
      html = described_class.new(applicant, template).compliance_status_badge

      expect(html).to include("Not Assessable", "bg-gray-100")
    end

    it "shows 'Compliant' once staff attested there are no corporate owners" do
      applicant.attest_no_corporate_owners!(by: create(:user))

      html = described_class.new(applicant.reload, template).compliance_status_badge

      expect(html).to include("Compliant", "bg-green-50")
    end
  end

  describe "#compliance_outcome_message" do
    it "explains why readiness cannot be assessed" do
      message = described_class.new(applicant, template).compliance_outcome_message

      expect(message).to include("No ownership has been captured")
    end
  end
end
