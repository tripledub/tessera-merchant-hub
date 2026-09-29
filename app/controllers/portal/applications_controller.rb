# frozen_string_literal: true

class Portal::ApplicationsController < Portal::BaseController
  include Portal::AbuseProtection

  before_action -> { reject_oversized_portal_payload(APPLICATION_PAYLOAD_LIMIT) }, only: :update
  rate_limit to: 60, within: 1.minute, by: -> { current_applicant.id }, with: :portal_rate_limited,
             store: portal_rate_limit_store, only: :update

  def show
    created = current_applicant.onboarding_application.nil?
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application

    return redirect_to portal_application_path(step: @application.current_step) if params[:step].blank? && !created

    @step = params[:step].presence || @application.current_step
    return head :not_found unless OnboardingApplication::STEPS.include?(@step)
    return redirect_to portal_application_path(step: @application.current_step) unless accessible_step?(@step)

    prepare_company_details if @step == "company"
    prepare_currencies if @step == "currencies"
    prepare_principals if @step == "principals"
  end

  def update
    @application = OnboardingApplications::FindOrCreate.call(applicant: current_applicant)
    authorize @application
    step = params.require(:step)
    return update_company if step == "company"
    return update_fulfilment if step == "fulfilment"
    return update_currencies if step == "currencies"
    return update_processing if step == "processing"
    return update_payments if step == "payments"
    return update_descriptor if step == "descriptor"
    return update_principals if step == "principals"
    return update_review if step == "review"

    OnboardingApplications::Advance.call(application: @application, step: step)
    redirect_to portal_application_path(step: @application.current_step)
  rescue OnboardingApplications::Advance::StepConflict
    redirect_to portal_application_path(step: @application.current_step), alert: t("portal.applications.progress_conflict")
  end

  private

  def accessible_step?(step)
    step == @application.current_step || @application.completed_steps.include?(step)
  end

  def update_company
    attributes = company_params
    same_as_registered = ActiveModel::Type::Boolean.new.cast(attributes.delete(:trading_address_same_as_registered))
    mirror_trading_address!(attributes) if same_as_registered

    if OnboardingApplications::SaveCompanyDetails.call(application: @application, attributes: attributes)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "company"
      prepare_company_details
      render :show, status: :unprocessable_content
    end
  end

  def prepare_company_details
    unless @application.applicant.primary_business_address
      @application.applicant.build_primary_business_address(primary: true)
    end
    @application.applicant.build_trading_address(primary: true) unless @application.applicant.trading_address
    @application.applicant.applicant_domains.build if @application.applicant.applicant_domains.empty?
    @trading_address_same_as_registered = trading_address_matches_registered?(@application.applicant)
  end

  def trading_address_matches_registered?(applicant)
    trading = applicant.trading_address
    return true if trading.nil? || trading.line1.blank?

    registered = applicant.primary_business_address
    return false if registered.nil?

    %i[line1 line2 city postcode country].all? { |field| trading.public_send(field) == registered.public_send(field) }
  end

  # Mirrors the registered address onto the trading address attributes so a
  # checked "same as registered" box never creates a second, distinct address
  # record — it keeps the existing trading address row (if any) but overwrites
  # its fields, rather than leaving it blank or duplicating data entry.
  def mirror_trading_address!(attributes)
    applicant_attrs = attributes[:applicant_attributes]
    registered = applicant_attrs&.[](:primary_business_address_attributes)
    return if registered.blank?

    mirrored = registered.to_h.except("id")
    trading_id = applicant_attrs.dig(:trading_address_attributes, :id)
    mirrored["id"] = trading_id if trading_id.present?
    applicant_attrs[:trading_address_attributes] = mirrored
  end

  def update_fulfilment
    if OnboardingApplications::SaveFulfilmentDetails.call(application: @application, attributes: fulfilment_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "fulfilment"
      render :show, status: :unprocessable_content
    end
  end

  def update_currencies
    if OnboardingApplications::SaveCurrencies.call(application: @application, attributes: currencies_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "currencies"
      prepare_currencies
      render :show, status: :unprocessable_content
    end
  end

  def prepare_currencies
    @application.processing_currencies.build if @application.processing_currencies.empty?
    @application.settlement_currencies.build if @application.settlement_currencies.empty?
  end

  def update_processing
    if OnboardingApplications::SaveProcessingHistory.call(application: @application, attributes: processing_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "processing"
      render :show, status: :unprocessable_content
    end
  end

  def update_payments
    if OnboardingApplications::SavePaymentDetails.call(application: @application, attributes: payment_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "payments"
      render :show, status: :unprocessable_content
    end
  end

  def update_descriptor
    if OnboardingApplications::SaveDescriptorDetails.call(application: @application, attributes: descriptor_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "descriptor"
      render :show, status: :unprocessable_content
    end
  end

  def update_principals
    if OnboardingApplications::SavePrincipals.call(application: @application, attributes: principals_params)
      redirect_to portal_application_path(step: @application.current_step), notice: t("portal.applications.saved")
    else
      @step = "principals"
      prepare_principals
      render :show, status: :unprocessable_content
    end
  end

  def prepare_principals
    principals = @application.applicant.kyc_principals.to_a.reject(&:merged?).reject(&:marked_for_destruction?)
    @application.applicant.kyc_principals.build(source: :applicant_declared) if principals.empty?
  end

  def update_review
    if OnboardingApplications::Submit.call(application: @application)
      redirect_to portal_application_path(step: "review"), notice: t("portal.applications.submitted")
    else
      @step = "review"
      render :show, status: :unprocessable_content
    end
  end

  def company_params
    params.require(:onboarding_application).permit(
      :eu_entity_details,
      :referrer,
      :business_model_description,
      :test_login_details,
      :operating_licence,
      :trading_address_same_as_registered,
      applicant_attributes: [
        :id,
        :company_name,
        :company_number,
        :sector,
        { primary_business_address_attributes: %i[id line1 line2 city postcode country],
          trading_address_attributes: %i[id line1 line2 city postcode country],
          applicant_domains_attributes: %i[id name _destroy] }
      ]
    )
  end

  def fulfilment_params
    params.require(:onboarding_application).permit(
      :delivery_over_seven_days,
      :full_payment_before_delivery,
      :takes_deposits,
      :deposit_percentage,
      :remaining_balance_due,
      :service_requirements,
      :integration_type
    )
  end

  def currencies_params
    params.require(:onboarding_application).permit(
      processing_currencies_attributes: %i[id code _destroy],
      settlement_currencies_attributes: %i[id code _destroy]
    )
  end

  def processing_params
    params.require(:onboarding_application).permit(:currently_accepts_card_payments, :current_acquirer)
  end

  def payment_params
    params.require(:onboarding_application).permit(
      :uses_shopping_cart,
      :shopping_cart_provider,
      :takes_recurring_payments,
      :sends_recurring_payment_receipts,
      :sends_recurring_payment_advance_notifications
    )
  end

  def descriptor_params
    params.require(:onboarding_application).permit(
      :descriptor,
      :descriptor_company_number,
      :descriptor_company_city
    )
  end

  def principals_params
    params.require(:onboarding_application).permit(
      applicant_attributes: [
        :id,
        { kyc_principals_attributes: %i[id name date_of_birth email role ownership_percentage _destroy] }
      ]
    )
  end
end
