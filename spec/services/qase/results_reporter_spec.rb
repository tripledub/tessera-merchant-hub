# frozen_string_literal: true

require "rails_helper"

RSpec.describe Qase::ResultsReporter do
  let(:report_path) { Rails.root.join("tmp/qase_results_reporter_spec.json") }
  let(:report) do
    [
      { case_id: 1, status: "passed", comment: nil },
      { case_id: 4, status: "failed", comment: "boom" }
    ]
  end

  before { File.write(report_path, report.to_json) }
  after { FileUtils.rm_f(report_path) }

  describe "#call" do
    context "when no token is available (credentials nor env var)" do
      it "raises without making a request" do
        allow(Rails.application.credentials).to receive(:dig).with(:qase, :api_key).and_return(nil)

        reporter = described_class.new(report_path: report_path, run_title: "Spec run", api_token: nil)

        expect { reporter.call }.to raise_error(described_class::Error, /No Qase API token/)
        expect(WebMock).not_to have_requested(:post, /api\.qase\.io/)
      end
    end

    context "when the report file does not exist" do
      it "raises" do
        FileUtils.rm_f(report_path)
        reporter = described_class.new(report_path: report_path, run_title: "Spec run", api_token: "token")

        expect { reporter.call }.to raise_error(described_class::Error, /No report at/)
      end
    end

    context "when the report has no qase_id-tagged examples" do
      it "raises" do
        File.write(report_path, "[]")
        reporter = described_class.new(report_path: report_path, run_title: "Spec run", api_token: "token")

        expect { reporter.call }.to raise_error(described_class::Error, /No qase_id-tagged examples/)
      end
    end

    context "when a token and a populated report are present" do
      let(:reporter) { described_class.new(report_path: report_path, run_title: "Spec run", api_token: "test-token") }

      before do
        stub_request(:post, "https://api.qase.io/v1/run/MH")
          .with(
            headers: { "Token" => "test-token", "Content-Type" => "application/json" },
            body: { title: "Spec run", cases: [ 1, 4 ], is_autotest: true }.to_json
          )
          .to_return(status: 200, body: { status: true, result: { id: 42 } }.to_json)

        stub_request(:post, "https://api.qase.io/v1/result/MH/42/bulk")
          .with(
            headers: { "Token" => "test-token" },
            body: {
              results: [
                { case_id: 1, status: "passed", comment: nil },
                { case_id: 4, status: "failed", comment: "boom" }
              ]
            }.to_json
          )
          .to_return(status: 200, body: { status: true, result: [] }.to_json)
      end

      it "creates a run and posts the results, returning the run id" do
        expect(reporter.call).to eq(42)
      end
    end

    context "when Qase returns an error" do
      it "raises with the response body" do
        stub_request(:post, "https://api.qase.io/v1/run/MH")
          .to_return(status: 401, body: { status: false, errorMessage: "Invalid token" }.to_json)

        reporter = described_class.new(report_path: report_path, run_title: "Spec run", api_token: "bad-token")

        expect { reporter.call }.to raise_error(described_class::Error, /Qase API error/)
      end
    end
  end

  describe "token resolution" do
    it "prefers the qase.api_key credential over QASE_API_TOKEN" do
      allow(Rails.application.credentials).to receive(:dig).with(:qase, :api_key).and_return("from-credentials")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("QASE_API_TOKEN", nil).and_return("from-env")

      reporter = described_class.new(report_path: report_path, run_title: "Spec run")

      expect(reporter.instance_variable_get(:@api_token)).to eq("from-credentials")
    end

    it "falls back to QASE_API_TOKEN when no credential is set" do
      allow(Rails.application.credentials).to receive(:dig).with(:qase, :api_key).and_return(nil)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("QASE_API_TOKEN", nil).and_return("from-env")

      reporter = described_class.new(report_path: report_path, run_title: "Spec run")

      expect(reporter.instance_variable_get(:@api_token)).to eq("from-env")
    end
  end
end
