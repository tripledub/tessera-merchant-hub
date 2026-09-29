# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecurityEventLogger do
  it "records useful security context without raw source or request data" do
    request = instance_double(
      ActionDispatch::Request,
      path_parameters: { controller: "portal/invitations", action: "show", token: "secret-token" },
      request_id: "request-123",
      remote_ip: "192.0.2.10"
    )

    allow(Rails.logger).to receive(:warn)

    described_class.log(event: "portal.invalid_access", request: request)

    expect(Rails.logger).to have_received(:warn) do |payload|
      expect(payload).to include("portal.invalid_access", "portal/invitations", "request-123", "source_fingerprint")
      expect(payload).not_to include("secret-token", "192.0.2.10", "applicant@example.com")
    end
  end
end
