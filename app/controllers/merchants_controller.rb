class MerchantsController < ApplicationController
  # PSP-admin onboarding: provision a merchant + first shop in tessera-core
  # (ADR-007) and create the merchant's first merchant_admin portal user.
  def new
    authorize Tessera::Merchant, :new?, policy_class: MerchantPolicy
  end

  def create
    authorize Tessera::Merchant, :create?, policy_class: MerchantPolicy

    if onboarding_params_incomplete?
      flash.now[:alert] = "Merchant name, shop name and admin email are all required."
      return render :new, status: :unprocessable_entity
    end

    merchant = ControlPlane::MerchantProvisioner.create!(**merchant_params)
    ControlPlane::ShopProvisioner.create!(merchant_id: merchant["merchant_id"], **shop_params)
    create_first_admin(merchant["merchant_id"])

    redirect_to authenticated_root_path,
                notice: "Merchant onboarded. An invite has been sent to #{admin_email}."
  rescue TesseraCoreClient::Error => e
    flash.now[:alert] = "Onboarding failed: #{e.message}"
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Could not create the admin user: #{e.record.errors.full_messages.to_sentence}"
    render :new, status: :unprocessable_entity
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
end
