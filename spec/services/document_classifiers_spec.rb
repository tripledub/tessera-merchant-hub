# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentClassifiers do
  describe ".obtain" do
    subject(:result) { described_class.obtain(condition) }

    let(:condition) { DocumentClassifiers::Condition.new(filename: filename, content_type: "application/pdf") }

    # Test against actual sample KYC filenames
    {
      "Andrew Bui - Passport - 16-11-2027.pdf" => :passport,
      "Ben Boulter - Passport - 20-03-2030.jpg" => :passport,
      "Andrew Bui - Utility Bill - 1-03-2026.pdf" => :utility_bill,
      "Ben Boulter - Utility Bill - 12-03-2026.pdf" => :utility_bill,
      "Insert Money Ltd - Certificate of Incorporation - 29-01-2026.pdf" => :certificate_of_incorporation,
      "SANDRET - Certificate of Incorporation.pdf" => :certificate_of_incorporation,
      "Insert Money Ltd - Memorandum Of Association 29-01-2026.pdf" => :memorandum_of_association,
      "Tab Trade - Amended Memorandum of Association.pdf" => :memorandum_of_association,
      "Tab Trade - Amended Articles of Association.pdf" => :articles_of_association,
      "Tab Trade - Certificate of Amendment - 30-01-2026.pdf" => :certificate_of_amendment,
      "Insert Money Ltd - Certificate of Directors 29-01-2026.pdf" => :certificate_of_directors,
      "Insert Money Ltd - Certificate of shareholder - 29-01-2026.pdf" => :certificate_of_shareholders,
      "Tab Trade - Share Certificate.pdf" => :share_certificate,
      "Tab Trade - Register of Member and Share Ledger.pdf" => :register_of_members,
      "Tab Trade - Certificate of Incumbency.pdf" => :certificate_of_incumbency,
      "Tab Trade - Group Structure Chart.png" => :group_structure_chart,
      "Insert Money Ltd - Certificate of registered address - 29-01-2026.pdf" => :certificate_of_registered_address,
      "Tab Trade - Confirmation of registered address - 03-04-2026.pdf" => :certificate_of_registered_address,
      "Insert Money Ltd - Bank Account Statement - 26-02-2026.pdf" => :bank_account_statement,
      "Tab Trade - Bank Account Statement - 16-02-2026.pdf" => :bank_account_statement,
      "KEYBOARD GROUP EXTRACT - 20260507.pdf" => :transaction_extract,
      "Insert Money Ltd - Funds_Flow_Diagram.pdf" => :funds_flow_diagram,
      "TabTrade - Business Plan & Projections.pdf" => :business_plan,
      "PAYMID - APM SUMMARY USD TO 20260505.csv" => :apm_summary,
      "Tab Trade - Legal Opinion.pdf" => :legal_opinion,
      "SANDRET - Declaration of trust Sandret to Keyboard.pdf" => :declaration_of_trust,
      "Insert Money Ltd & TabTrade - Payment Agreement.pdf" => :payment_agreement,
      "Tab Trade - Anti-Money Laundering and Counter-Terrorism Financing Policy.pdf" => :aml_ctf_policy,
      "Tab Trade - AML_KYC Requirements.pdf" => :aml_kyc_requirements,
      "Paystrax - Source Of Wealth Questionnaire - SIGNED.pdf" => :source_of_wealth_questionnaire,
      "Paystrax - AML CTF questionnaire v1.1 (2).pdf" => :aml_ctf_questionnaire
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
    it "raises NoHandlerAccepted when no default is set" do
      condition = DocumentClassifiers::Condition.new(filename: "mystery_doc.pdf", content_type: "application/pdf")
      expect { described_class.obtain(condition) }
        .to raise_error(HandlerRegisterable::NoHandlerAccepted)
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
