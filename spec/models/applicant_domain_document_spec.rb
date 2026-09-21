# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantDomainDocument, type: :model do
  subject(:link) { build(:applicant_domain_document) }

  it { is_expected.to belong_to(:applicant_domain) }
  it { is_expected.to belong_to(:kyc_document) }

  it "is valid for a proof-of-domain document of the same applicant" do
    expect(link).to be_valid
  end

  it "rejects the same document linked twice to one domain" do
    link.save!
    duplicate = build(:applicant_domain_document,
      applicant_domain: link.applicant_domain, kyc_document: link.kyc_document)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:kyc_document_id]).to be_present
  end

  it "allows one document to evidence several domains, and one domain several documents" do
    first = create(:applicant_domain_document)
    applicant = first.applicant_domain.applicant
    other_domain = create(:applicant_domain, applicant: applicant)
    other_document = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)

    expect(build(:applicant_domain_document, applicant_domain: other_domain, kyc_document: first.kyc_document)).to be_valid
    expect(build(:applicant_domain_document, applicant_domain: first.applicant_domain, kyc_document: other_document)).to be_valid
  end

  it "rejects a document belonging to a different applicant" do
    link.kyc_document = create(:kyc_document, document_type: :proof_of_domain_ownership)

    expect(link).not_to be_valid
    expect(link.errors[:kyc_document]).to include("must belong to the same applicant as the domain")
  end

  it "rejects a document that is not a proof of domain ownership" do
    link.kyc_document = create(:kyc_document, applicant: link.applicant_domain.applicant, document_type: :passport)

    expect(link).not_to be_valid
    expect(link.errors[:kyc_document]).to include("must be a proof of domain ownership document")
  end

  it "does not re-check the document type once the link exists (a later reclassification keeps it)" do
    link.save!
    link.kyc_document.update!(document_type: :other)

    expect(link.reload).to be_valid
  end
end
