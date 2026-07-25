# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingSessionPresenter, type: :presenter do
  let(:template) do
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.view_context
  end
  let(:session) do
    create(:onboarding_session, status: :in_progress, current_stage: :ownership,
      completed_stages: %w[company_info directors_ubos],
      created_at: Time.zone.parse("2026-07-23 09:00"),
      updated_at: Time.zone.parse("2026-07-23 10:30"))
  end
  let(:presenter) { described_class.new(session, template) }

  it "summarises message counts by speaker" do
    create(:onboarding_message, onboarding_session: session, role: :applicant)
    create_list(:onboarding_message, 2, onboarding_session: session, role: :bot)

    expect(presenter.message_count).to eq(3)
    expect(presenter.applicant_message_count).to eq(1)
    expect(presenter.bot_message_count).to eq(2)
  end

  it "reports zero counts for a session without messages" do
    expect(presenter.message_count).to eq(0)
    expect(presenter.stage_groups).to be_empty
  end

  it "calculates progress across the six onboarding stages" do
    expect(presenter.progress_percentage).to eq(33)
  end

  it "ignores unknown and duplicate completed stages" do
    session.update!(completed_stages: %w[company_info company_info unknown])

    expect(presenter.progress_percentage).to eq(17)
  end

  it "exposes human labels and session timing" do
    expect(presenter.status_label).to eq("In progress")
    expect(presenter.stage_label).to eq("Ownership")
    expect(presenter.started_at).to eq(Time.zone.parse("2026-07-23 09:00"))
    expect(presenter.last_activity_at).to eq(Time.zone.parse("2026-07-23 10:30"))
    expect(presenter.elapsed_duration).to eq("about 2 hours")
  end

  it "uses the latest message as last activity when it is newer than the session" do
    message = create(:onboarding_message, onboarding_session: session,
      created_at: Time.zone.parse("2026-07-23 11:00"))

    expect(presenter.last_activity_at).to eq(message.created_at)
    expect(presenter.elapsed_duration).to eq("about 2 hours")
  end

  it "uses contiguous stage groups without changing transcript chronology" do
    create(:onboarding_message, onboarding_session: session, stage: "company_info",
      content: "First", created_at: 3.minutes.ago)
    create(:onboarding_message, onboarding_session: session, stage: "directors_ubos",
      content: "Second", created_at: 2.minutes.ago)
    create(:onboarding_message, onboarding_session: session, stage: "company_info",
      content: "Third", created_at: 1.minute.ago)

    expect(presenter.stage_groups.map { |group| group[:stage] })
      .to eq(%w[company_info directors_ubos company_info])
    expect(presenter.stage_groups.flat_map { |group| group[:messages] }.map(&:content))
      .to eq(%w[First Second Third])
  end

  it "retains messages with missing or unknown stages" do
    create(:onboarding_message, onboarding_session: session, stage: nil, content: "Missing")
    create(:onboarding_message, onboarding_session: session, stage: "future_stage", content: "Future")

    unknown_group = presenter.stage_groups.fetch(0)
    expect(unknown_group[:stage]).to eq("unknown")
    expect(unknown_group[:label]).to eq("Unknown stage")
    expect(unknown_group[:messages].map(&:content)).to contain_exactly("Missing", "Future")
  end

  describe "#plain_text_transcript" do
    it "formats a single message as [timestamp] role/stage: content" do
      create(:onboarding_message, onboarding_session: session, role: :applicant, stage: "company_info",
        content: "The company is Acme Ltd", created_at: Time.zone.parse("2026-06-26 18:42:10"))

      expect(presenter.plain_text_transcript).to eq(
        "[2026-06-26 18:42:10] applicant/company_info: The company is Acme Ltd"
      )
    end

    it "joins multiple messages with newlines in chronological order" do
      create(:onboarding_message, onboarding_session: session, role: :bot, stage: "company_info",
        content: "Welcome", created_at: Time.zone.parse("2026-06-26 18:42:00"))
      create(:onboarding_message, onboarding_session: session, role: :applicant, stage: "company_info",
        content: "Hi there", created_at: Time.zone.parse("2026-06-26 18:42:10"))

      expect(presenter.plain_text_transcript).to eq(
        "[2026-06-26 18:42:00] bot/company_info: Welcome\n" \
        "[2026-06-26 18:42:10] applicant/company_info: Hi there"
      )
    end

    it "falls back to unknown for an invalid or missing stage" do
      create(:onboarding_message, onboarding_session: session, role: :bot, stage: nil,
        content: "No stage", created_at: Time.zone.parse("2026-06-26 18:42:00"))

      expect(presenter.plain_text_transcript).to eq(
        "[2026-06-26 18:42:00] bot/unknown: No stage"
      )
    end

    it "returns an empty string for a session with no messages" do
      expect(presenter.plain_text_transcript).to eq("")
    end
  end
end
