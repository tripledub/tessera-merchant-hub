# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transcripts::IndexQuery do
  subject(:results) { described_class.new(OnboardingSession.all, filters).call }

  let(:filters) { {} }
  let(:first_applicant) { create(:applicant) }
  let(:second_applicant) { create(:applicant) }
  let!(:older_session) do
    create(:onboarding_session, applicant: first_applicant, status: :completed,
      current_stage: :document_collection, created_at: Date.new(2026, 7, 10), updated_at: Date.new(2026, 7, 11))
  end
  let!(:newer_session) do
    create(:onboarding_session, applicant: second_applicant, status: :in_progress,
      current_stage: :ownership, created_at: Date.new(2026, 7, 20), updated_at: Date.new(2026, 7, 22))
  end

  it "orders sessions by most recent activity" do
    expect(results.map(&:id)).to eq([ newer_session.id, older_session.id ])
  end

  it "treats a newer message as session activity" do
    create(:onboarding_message, onboarding_session: older_session, created_at: Date.new(2026, 7, 23))

    expect(results.map(&:id)).to eq([ older_session.id, newer_session.id ])
    expect(results.first.last_activity_at.to_date).to eq(Date.new(2026, 7, 23))
  end

  it "filters by applicant" do
    filters[:applicant_id] = first_applicant.id

    expect(results).to contain_exactly(older_session)
  end

  it "combines status and stage filters" do
    filters.merge!(status: "completed", current_stage: "document_collection")

    expect(results).to contain_exactly(older_session)
  end

  it "filters inclusively by start date" do
    filters[:date_from] = "2026-07-20"

    expect(results).to contain_exactly(newer_session)
  end

  it "filters inclusively by end date" do
    filters[:date_to] = "2026-07-10"

    expect(results).to contain_exactly(older_session)
  end

  it "ignores invalid enum and date filters" do
    filters.merge!(status: "not-a-status", current_stage: "nope", date_from: "invalid", date_to: "also-invalid")

    expect { results.load }.not_to raise_error
    expect(results.map(&:id)).to eq([ newer_session.id, older_session.id ])
  end

  it "ignores a malformed applicant id" do
    filters[:applicant_id] = "not-a-uuid"

    expect { results.load }.not_to raise_error
    expect(results.map(&:id)).to eq([ newer_session.id, older_session.id ])
  end

  it "provides aggregate message counts" do
    create_list(:onboarding_message, 2, onboarding_session: newer_session)

    expect(results.find { |session| session.id == newer_session.id }.messages_count).to eq(2)
  end
end
