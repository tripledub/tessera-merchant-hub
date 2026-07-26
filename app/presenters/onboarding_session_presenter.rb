# frozen_string_literal: true

class OnboardingSessionPresenter < BasePresenter
  presents :onboarding_session

  def message_count
    messages.size
  end

  def applicant_message_count
    messages.count(&:applicant?)
  end

  def bot_message_count
    messages.count(&:bot?)
  end

  def progress_percentage
    ((valid_completed_stages.size.to_f / OnboardingSession.current_stages.size) * 100).round
  end

  def started_at
    onboarding_session.created_at
  end

  def last_activity_at
    [ onboarding_session.updated_at, messages.last&.created_at ].compact.max
  end

  def elapsed_duration
    distance_of_time_in_words(started_at, last_activity_at)
  end

  def status_label
    onboarding_session.status.humanize
  end

  def stage_label
    onboarding_session.current_stage.humanize
  end

  def stage_groups
    messages.each_with_object([]) do |message, groups|
      stage = valid_stage(message.stage)
      if groups.last&.dig(:stage) == stage
        groups.last[:messages] << message
      else
        groups << {
          stage: stage,
          label: stage == "unknown" ? "Unknown stage" : stage.humanize,
          messages: [ message ]
        }
      end
    end
  end

  def plain_text_transcript
    messages.map do |message|
      "[#{message.created_at.strftime('%Y-%m-%d %H:%M:%S')}] #{message.role}/#{valid_stage(message.stage)}: #{message.content}"
    end.join("\n")
  end

  def document_checklist_items
    Onboarding::DocumentCollectionService.received_documents(onboarding_session)
  end

  def document_status_label(item)
    return "Received" if item["received"]
    return "Deferred" if item["deferred"]

    "Outstanding"
  end

  private

  def messages
    @messages ||= onboarding_session.onboarding_messages.order(:created_at, :id).to_a
  end

  def valid_completed_stages
    Array(onboarding_session.completed_stages).uniq & OnboardingSession.current_stages.keys
  end

  def valid_stage(stage)
    OnboardingSession.current_stages.key?(stage) ? stage : "unknown"
  end
end
