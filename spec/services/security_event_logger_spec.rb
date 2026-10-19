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

  describe ".log_event (no request, for services)" do
    it "logs the event and its details as structured JSON" do
      allow(Rails.logger).to receive(:warn)

      described_class.log_event(event: "portal.sign_in_code.wrong", code_id: "abc-123", attempts: 2)

      expect(Rails.logger).to have_received(:warn) do |payload|
        expect(JSON.parse(payload)).to include("event" => "portal.sign_in_code.wrong", "code_id" => "abc-123", "attempts" => 2)
      end
    end
  end

  describe ".fingerprint" do
    it "is a stable keyed hash that does not reveal the value" do
      first = described_class.fingerprint("applicant@example.com")

      expect(described_class.fingerprint("applicant@example.com")).to eq(first)
      expect(described_class.fingerprint("other@example.com")).not_to eq(first)
      expect(first).not_to include("applicant")
      expect(first).to match(/\A\h{64}\z/)
    end

    it "uses a key of its own, so it cannot be matched against the source fingerprints" do
      request = instance_double(ActionDispatch::Request, path_parameters: {}, request_id: "r", remote_ip: "192.0.2.10")
      allow(Rails.logger).to receive(:warn)
      described_class.log(event: "x", request: request)

      expect(Rails.logger).to have_received(:warn) do |payload|
        expect(payload).not_to include(described_class.fingerprint("192.0.2.10"))
      end
    end
  end
end
