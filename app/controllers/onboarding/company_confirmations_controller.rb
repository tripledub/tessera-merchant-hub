# frozen_string_literal: true

module Onboarding
  class CompanyConfirmationsController < Portal::BaseController
    ANSWERS = %w[yes no].freeze

    def create
      return head :unprocessable_content unless ANSWERS.include?(params[:answer])

      session = current_applicant.onboarding_session || current_applicant.create_onboarding_session!
      return redirect_to portal_onboarding_path unless Onboarding::CompanyIdentityConfirmation.pending?(session)

      if params[:answer] == "yes"
        Onboarding::CompanyIdentityConfirmation.confirm!(session)
      else
        Onboarding::CompanyIdentityConfirmation.decline!(session)
      end

      redirect_to portal_onboarding_path
    end
  end
end
