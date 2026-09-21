# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::AddDomainByHand, type: :service do
  let(:author)    { create(:user, :psp_admin) }
  let(:applicant) { create(:applicant) }
  let(:domain)    { ApplicantDomain.new(applicant: applicant) }

  def call(name: "handadded.com", justification: "Client showed us the registrar account.")
    described_class.call(domain: domain, name: name, justification: justification, author: author)
  end

  it "creates an accepted, manual domain together with the author's comment" do
    expect(call).to be(true)

    expect(domain).to be_persisted
    expect(domain).to be_accepted
    expect(domain).to be_source_manual
    comment = domain.comments.sole
    expect(comment.body).to eq("Client showed us the registrar account.")
    expect(comment.author).to eq(author)
  end

  it "refuses a blank justification and creates nothing" do
    expect { expect(call(justification: "  ")).to be(false) }
      .not_to change { [ ApplicantDomain.count, Comment.count ] }

    expect(domain).not_to be_persisted
    expect(domain.errors[:justification]).to be_present
  end

  it "refuses an invalid name and creates no comment" do
    expect { expect(call(name: "not a domain")).to be(false) }
      .not_to change { [ ApplicantDomain.count, Comment.count ] }

    expect(domain.errors[:name]).to be_present
  end

  it "refuses a domain the applicant already has, whatever the case" do
    create(:applicant_domain, applicant: applicant, name: "Handadded.com")

    expect { expect(call).to be(false) }.not_to change(Comment, :count)

    expect(domain.errors[:name]).to be_present
  end

  it "keeps what was typed so the form can be shown again with its errors" do
    call(name: "not a domain", justification: "")

    expect(domain.name).to eq("not a domain")
    expect(domain.justification).to eq("")
  end

  it "reports both problems together" do
    call(name: "not a domain", justification: "")

    expect(domain.errors.attribute_names).to include(:name, :justification)
  end

  it "does not leave a domain behind if the comment cannot be saved" do
    allow_any_instance_of(Comment).to receive(:save!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

    expect { call }.to raise_error(ActiveRecord::RecordInvalid)

    expect(ApplicantDomain.count).to eq(0)
  end
end
