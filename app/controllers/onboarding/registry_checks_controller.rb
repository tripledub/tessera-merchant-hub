# frozen_string_literal: true

module Onboarding
  # MH-391: the applicant's Yes or No on the company the registry found for their number.
  class RegistryChecksController < Portal::BaseController
    ANSWERS = %w[yes no].freeze

    def create
      return head :unprocessable_content unless ANSWERS.include?(params[:answer])

      session = current_applicant.onboarding_session || current_applicant.create_onboarding_session!

      if params[:answer] == "yes"
        Onboarding::RegistryCompanyCheck.confirm!(session)
      else
        Onboarding::RegistryCompanyCheck.decline!(session)
      end

      redirect_to portal_onboarding_path
    end
  end
end
