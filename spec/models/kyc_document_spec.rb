# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycDocument, type: :model do
  subject(:document) { build(:kyc_document) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to belong_to(:kyc_principal).optional }
  it { is_expected.to belong_to(:processing_statement).optional }

  it { is_expected.to have_many(:domain_links).class_name("ApplicantDomainDocument").dependent(:delete_all) }
  it { is_expected.to have_many(:evidenced_domains).through(:domain_links).source(:applicant_domain) }

  it "removes its evidence links but not the domains when destroyed" do
    link = create(:applicant_domain_document)

    link.kyc_document.destroy!

    expect(ApplicantDomainDocument.exists?(link.id)).to be(false)
    expect(ApplicantDomain.exists?(link.applicant_domain_id)).to be(true)
  end

  it "no longer links to an applicant domain (MH-296)" do
    expect(described_class.column_names).not_to include("applicant_domain_id")
    expect(described_class.reflect_on_association(:applicant_domain)).to be_nil
  end

  it "defaults status to pending" do
    expect(document.status).to eq("pending")
  end

  it "has no comment_status by default" do
    expect(document.comment_status).to be_nil
  end

  it "defines the comment_status enum" do
    expect(described_class.comment_statuses).to eq(
      "requires_follow_up" => 0,
      "resolved" => 1
    )
  end

  it "can carry comments via the Commentable concern" do
    document = create(:kyc_document)
    comment  = create(:comment, commentable: document, author: create(:user, :psp_admin))

    expect(document.comments).to contain_exactly(comment)
  end

  it "destroys along with its comments (comments are append-only/readonly and must not block cascade delete)" do
    document = create(:kyc_document)
    comment  = create(:comment, commentable: document, author: create(:user, :psp_admin))

    expect { document.destroy! }.not_to raise_error
    expect(described_class.exists?(document.id)).to be false
    expect(Comment.exists?(comment.id)).to be false
  end

  it "defines the crypto policy document types" do
    expect(described_class.document_types).to include(
      "vasp_registration" => 74,
      "wallet_custody_infrastructure_attestation" => 75
    )
  end

  it "defines the processing statement document type" do
    expect(described_class.document_types).to include("processing_statement" => 55)
  end

  it "defines the proof of domain ownership document type" do
    expect(described_class.document_types).to include("proof_of_domain_ownership" => 80)
  end

  it "offers proof of domain ownership as manually selectable" do
    expect(described_class.manually_selectable_document_types).to include("proof_of_domain_ownership")
  end

  it "keeps processing statements out of manually selectable document types" do
    expect(described_class.manually_selectable_document_types).not_to include("processing_statement")
  end

  it "allows a suggested spreadsheet to be confirmed as a processing statement" do
    document.file.attach(
      io: StringIO.new("spreadsheet"),
      filename: "statement.csv",
      content_type: "text/csv"
    )
    document.document_type = :processing_statement

    expect(document.selectable_document_types).to include("processing_statement")
  end

  it "does not offer processing statements for non-spreadsheet documents" do
    expect(document.selectable_document_types).not_to include("processing_statement")
  end

  it "requires an attached file" do
    document.file = nil
    expect(document).not_to be_valid
    expect(document.errors[:file]).not_to be_empty
  end

  it "rejects files larger than the upload limit" do
    document.file.attach(
      io: StringIO.new("x" * (KycDocument::MAX_FILE_SIZE + 1)),
      filename: "large.pdf",
      content_type: "application/pdf"
    )

    expect(document).not_to be_valid
    expect(document.errors[:file]).to include("must be less than 10 MB")
  end

  it "can be assigned to a principal" do
    applicant  = create(:applicant)
    principal  = create(:kyc_principal, applicant: applicant)
    document   = build(:kyc_document, applicant: applicant, kyc_principal: principal)
    expect(document).to be_valid
  end

  it "can exist without a principal (company-level doc)" do
    document = build(:kyc_document, kyc_principal: nil)
    expect(document).to be_valid
  end

  describe ".document_type_label" do
    it "labels a nil type as Unclassified" do
      expect(described_class.document_type_label(nil)).to eq("Unclassified")
    end

    it "translates a known document type" do
      expect(described_class.document_type_label("passport")).to eq("Passport")
    end

    it "humanizes an unrecognized type as a fallback" do
      expect(described_class.document_type_label("some_new_type")).to eq("Some new type")
    end
  end

  describe ".ordered_by_review_priority" do
    it "orders processing, pending, error, then complete, oldest first within each status" do
      applicant = create(:applicant)
      complete   = create(:kyc_document, applicant: applicant, status: :complete)
      pending    = create(:kyc_document, applicant: applicant, status: :pending)
      error      = create(:kyc_document, applicant: applicant, status: :error)
      processing = create(:kyc_document, applicant: applicant, status: :processing)

      expect(applicant.kyc_documents.ordered_by_review_priority).to eq([ processing, pending, error, complete ])
    end
  end

  describe "#previewable?" do
    def document_with(content_type)
      create(:kyc_document).tap do |doc|
        doc.file.attach(io: StringIO.new("x"), filename: "f", content_type: content_type)
      end
    end

    it "is true for a PDF and for images, which the preview modal can show" do
      expect(document_with("application/pdf")).to be_previewable
      expect(document_with("image/png")).to be_previewable
      expect(document_with("image/jpeg")).to be_previewable
    end

    it "is false for spreadsheets and CSVs, which it cannot" do
      expect(document_with("text/csv")).not_to be_previewable
      expect(document_with("application/vnd.ms-excel")).not_to be_previewable
    end

    it "is false when no file is attached" do
      expect(described_class.new).not_to be_previewable
    end
  end

  # MH-301: only documents the matcher can attach to a person can meaningfully be "unlinked".
  describe "#principal_linkable?" do
    %w[passport driving_licence utility_bill bank_account_statement].each do |type|
      it "is true for #{type}, whose extraction schema can be matched to a person" do
        expect(build(:kyc_document, document_type: type)).to be_principal_linkable
      end
    end

    %w[
      proof_of_domain_ownership processing_statement register_of_members share_certificate
      articles_of_association certificate_of_incorporation certificate_of_incumbency
      certificate_of_registered_address group_structure_chart other
    ].each do |type|
      it "is false for #{type}, which the matcher never tries to link" do
        expect(build(:kyc_document, document_type: type)).not_to be_principal_linkable
      end
    end

    it "is false, without raising, for a document that has no type yet" do
      document = build(:kyc_document, document_type: nil)

      expect { document.principal_linkable? }.not_to raise_error
      expect(document).not_to be_principal_linkable
    end
  end

  # MH-302: which Documents-tab panel a document belongs in.
  describe "#status_group" do
    %w[unclassified auto_classified ai_suggested rejected].each do |classification|
      it "is :unconfirmed when classification_status is #{classification}, regardless of status" do
        document = build(:kyc_document, classification_status: classification, status: :complete)

        expect(document.status_group).to eq(:unconfirmed)
      end
    end

    %w[pending processing error].each do |status|
      it "is :confirmed when classification is confirmed but status is #{status}" do
        document = build(:kyc_document, classification_status: :confirmed, status: status)

        expect(document.status_group).to eq(:confirmed)
      end
    end

    it "is :processed when classification is confirmed and status is complete" do
      document = build(:kyc_document, classification_status: :confirmed, status: :complete)

      expect(document.status_group).to eq(:processed)
    end
  end
end
