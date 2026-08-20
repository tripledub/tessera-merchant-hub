# frozen_string_literal: true

module Kyc
  # Display and form-state decisions for confirming/correcting a
  # KycDocument's extracted validity dates (MH-196). Keeps this logic out of
  # views/controllers per the presenter convention.
  class DocumentDateConfirmationPresenter < BasePresenter
    presents :document

    def date_roles
      document.validity_dates.keys
    end

    def extracted_value_for(date_role)
      document.validity_dates.dig(date_role, "normalized")
    end

    def current_confirmation_for(date_role)
      @current_confirmations ||= {}
      @current_confirmations.fetch(date_role) do
        @current_confirmations[date_role] = Kyc::DocumentDateConfirmation.current_for(document, date_role)
      end
    end

    def confirmed?(date_role)
      current_confirmation_for(date_role).present?
    end

    # What the confirmation form should show as the value to confirm/correct:
    # the current confirmed value once one exists, otherwise the extracted
    # value (which may itself be nil, i.e. a missing date awaiting entry).
    def form_default_value_for(date_role)
      confirmation = current_confirmation_for(date_role)
      return confirmation.confirmed_value.iso8601 if confirmation

      extracted_value_for(date_role)
    end
  end
end
