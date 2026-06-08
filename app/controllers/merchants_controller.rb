class MerchantsController < ApplicationController
  expose(:merchant) { Merchant.find_by!(merchant_id: params[:id]) }

  # PSP-admin onboarding: provision a merchant + first shop in tessera-core
  # (ADR-007) and create the merchant's first merchant_admin portal user.
  def new
    authorize Tessera::Merchant, :new?, policy_class: MerchantPolicy
  end

  def create
    authorize Tessera::Merchant, :create?, policy_class: MerchantPolicy

    if onboarding_params_incomplete?
      flash.now[:alert] = I18n.t("flash.merchants.missing_fields")
      return render :new, status: :unprocessable_entity
    end

    merchant = ControlPlane::MerchantProvisioner.create!(**merchant_params)
    ControlPlane::ShopProvisioner.create!(merchant_id: merchant["merchant_id"], **shop_params)
    create_first_admin(merchant["merchant_id"])

    redirect_to authenticated_root_path,
                notice: I18n.t("flash.merchants.onboard_success", email: admin_email)
  rescue TesseraCoreClient::Error => e
    flash.now[:alert] = I18n.t("flash.merchants.onboard_failed", message: e.message)
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = I18n.t("flash.merchants.admin_create_failed", errors: e.record.errors.full_messages.to_sentence)
    render :new, status: :unprocessable_entity
  end

  def edit
    authorize merchant, policy_class: MerchantPolicy
  end

  def update
    authorize merchant, policy_class: MerchantPolicy
    result = Merchants::UpdateProfile.call(merchant, merchant_profile_params)
    if result.errors.none?
      redirect_to merchant_path(merchant),
                  notice: t("flash.merchants.update_success")
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def create_first_admin(merchant_id)
    user = User.create!(
      email: admin_email,
      password: SecureRandom.base58(24),
      role: :merchant_admin,
      merchant_id: merchant_id
    )
    user.send_reset_password_instructions
  end

  def onboarding_params_incomplete?
    admin_email.blank? || merchant_params[:name].blank? || shop_params[:name].blank?
  end

  def admin_email
    params.dig(:admin, :email).to_s.strip
  end

  def merchant_params
    params.fetch(:merchant, {}).permit(:name, :company_name, :country).to_h.symbolize_keys
  end

  def shop_params
    params.fetch(:shop, {}).permit(:name, :country).to_h.symbolize_keys
  end

  def merchant_profile_params
    params.fetch(:merchant, {}).permit(
      :contact_email, :support_url, :address_line1, :city, :country_code
    )
  end
end
