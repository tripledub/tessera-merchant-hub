# frozen_string_literal: true

# MH-397: what the applicant's dashboard shows: which of three states they are in,
# how far along they are, and what comes next. Progress and "next up" come from
# the snapshot the chat and the form share, so an answer counts whichever way it
# was given.
class ApplicantDashboardPresenter < BasePresenter
  presents :applicant_user

  # Percent, once started, never reaches 100 while anything is still missing.
  MAX_UNTIL_COMPLETE = 99

  def state
    return :submitted if application&.submitted?

    started? ? :in_progress : :not_started
  end

  def submitted? = state == :submitted

  def not_started? = state == :not_started

  def percentage
    return 0 if state == :not_started || snapshot.nil?
    return 100 if snapshot.next_action.nil?

    [ snapshot.progress.percentage, MAX_UNTIL_COMPLETE ].min
  end

  def next_up
    action = snapshot&.next_action
    return t("portal.applications.steps.#{OnboardingApplication::STEPS.first}") if application.nil?
    return t("portal.applications.steps.review") if action.nil?

    case action.step
    when OnboardingApplications::Snapshot::CHAT_STEP then t("portal.dashboard.show.next_up.chat")
    when OnboardingApplications::Snapshot::DOCUMENTS_STEP then t("portal.dashboard.show.next_up.documents")
    else t("portal.applications.steps.#{action.step}")
    end
  end

  # A first name when there is one (MH-407), otherwise plain wording.
  def heading
    return t("portal.dashboard.show.thank_you") if submitted?
    return t("portal.dashboard.show.welcome", name: applicant_user.first_name) if applicant_user.first_name.present?

    t("portal.dashboard.show.welcome_back")
  end

  def intro
    t("portal.dashboard.show.intro.#{state}")
  end

  private

  def applicant = applicant_user.applicant

  def application = applicant.onboarding_application

  def snapshot
    return if application.nil?

    @snapshot ||= OnboardingApplications::Snapshot.for(application)
  end

  def started?
    application&.completed_steps.present? || chat_started?
  end

  def chat_started?
    session = applicant.onboarding_session
    session.present? && (session.stage_data.present? || session.onboarding_messages.where(role: :applicant).exists?)
  end
end
