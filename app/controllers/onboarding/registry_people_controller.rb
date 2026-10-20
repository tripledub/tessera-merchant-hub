# frozen_string_literal: true

module Onboarding
  # MH-417: the applicant's Yes or No on a person the registry lists.
  class RegistryPeopleController < Portal::BaseController
    ANSWERS = %w[yes no].freeze

    def create
      return head :unprocessable_content unless ANSWERS.include?(params[:answer])

      session = current_applicant.onboarding_session || current_applicant.create_onboarding_session!

      if params[:answer] == "yes"
        Onboarding::RegistryPeople.confirm!(session)
      else
        Onboarding::RegistryPeople.decline!(session)
      end

      redirect_to portal_onboarding_path
    end
  end
end
