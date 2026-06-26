# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_session do
    applicant
    current_stage { :company_info }
    completed_stages { [] }
    stage_data { {} }
    document_checklist { {} }
    status { :in_progress }
  end
end
