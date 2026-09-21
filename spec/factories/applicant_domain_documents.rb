# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_domain_document do
    association :applicant_domain
    kyc_document do
      association :kyc_document, applicant: applicant_domain.applicant, document_type: :proof_of_domain_ownership
    end
  end
end
