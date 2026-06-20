# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentClassifiers do
  describe ".obtain" do
    subject(:result) { described_class.obtain(condition) }

    let(:condition) { DocumentClassifiers::Condition.new(filename: filename, content_type: "application/pdf") }

    {
      "John Smith - Passport - 16-11-2027.pdf" => :passport,
      "Jane Doe - Passport - 20-03-2030.jpg" => :passport,
      "John Smith - Utility Bill - 1-03-2026.pdf" => :utility_bill,
      "Jane Doe - Utility Bill - 12-03-2026.pdf" => :utility_bill,
      "Acme Ltd - Certificate of Incorporation - 29-01-2026.pdf" => :certificate_of_incorporation,
      "Globex Corp - Certificate of Incorporation.pdf" => :certificate_of_incorporation,
      "Acme Ltd - Memorandum Of Association 29-01-2026.pdf" => :memorandum_of_association,
      "Example Co - Amended Memorandum of Association.pdf" => :memorandum_of_association,
      "Example Co - Amended Articles of Association.pdf" => :articles_of_association,
      "Example Co - Certificate of Amendment - 30-01-2026.pdf" => :certificate_of_amendment,
      "Acme Ltd - Certificate of Directors 29-01-2026.pdf" => :certificate_of_directors,
      "Acme Ltd - Certificate of shareholder - 29-01-2026.pdf" => :certificate_of_shareholders,
      "Example Co - Share Certificate.pdf" => :share_certificate,
      "Example Co - Register of Member and Share Ledger.pdf" => :register_of_members,
      "Example Co - Certificate of Incumbency.pdf" => :certificate_of_incumbency,
      "Example Co - Group Structure Chart.png" => :group_structure_chart,
      "Acme Ltd - Certificate of registered address - 29-01-2026.pdf" => :certificate_of_registered_address,
      "Example Co - Confirmation of registered address - 03-04-2026.pdf" => :certificate_of_registered_address,
      "Acme Ltd - Bank Account Statement - 26-02-2026.pdf" => :bank_account_statement,
      "Example Co - Bank Account Statement - 16-02-2026.pdf" => :bank_account_statement,
      "HOLDINGS GROUP EXTRACT - 20260507.pdf" => :transaction_extract,
      "Acme Ltd - Funds_Flow_Diagram.pdf" => :funds_flow_diagram,
      "Example Co - Business Plan & Projections.pdf" => :business_plan,
      "PROCESSOR - APM SUMMARY USD TO 20260505.csv" => :apm_summary,
      "Example Co - Legal Opinion.pdf" => :legal_opinion,
      "Globex Corp - Declaration of trust Globex to Holdings.pdf" => :declaration_of_trust,
      "Acme Ltd & Example Co - Payment Agreement.pdf" => :payment_agreement,
      "Example Co - Anti-Money Laundering and Counter-Terrorism Financing Policy.pdf" => :aml_ctf_policy,
      "Example Co - AML_KYC Requirements.pdf" => :aml_kyc_requirements,
      "Processor Inc - Source Of Wealth Questionnaire - SIGNED.pdf" => :source_of_wealth_questionnaire,
      "Processor Inc - AML CTF questionnaire v1.1 (2).pdf" => :aml_ctf_questionnaire
    }.each do |sample_filename, expected_type|
      context "with '#{sample_filename}'" do
        let(:filename) { sample_filename }

        it "classifies as #{expected_type}" do
          expect(result.document_type).to eq(expected_type)
          expect(result.classify).to include(
            document_type: expected_type,
            classification_method: :rule_based,
            confidence: 1.0
          )
        end
      end
    end
  end

  describe ".obtain with unknown filename" do
    it "falls back to AI classifier" do
      condition = DocumentClassifiers::Condition.new(filename: "mystery_doc.pdf", content_type: "application/pdf")
      result = described_class.obtain(condition)
      expect(result).to be_a(DocumentClassifiers::AiFallback)
    end
  end

  describe ".registered_handlers" do
    it "has all expected handlers registered" do
      expect(described_class.registered_handlers.keys).to contain_exactly(
        :passport, :driving_licence, :utility_bill,
        :certificate_of_incorporation, :memorandum_of_association,
        :articles_of_association, :certificate_of_amendment,
        :certificate_of_directors, :certificate_of_shareholders,
        :share_certificate, :register_of_members,
        :certificate_of_incumbency, :group_structure_chart,
        :certificate_of_registered_address,
        :bank_account_statement, :transaction_extract,
        :funds_flow_diagram, :business_plan, :apm_summary,
        :legal_opinion, :declaration_of_trust, :payment_agreement,
        :aml_ctf_policy, :aml_kyc_requirements,
        :source_of_wealth_questionnaire, :aml_ctf_questionnaire
      )
    end
  end
end
