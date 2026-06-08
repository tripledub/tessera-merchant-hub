class ShopsController < ApplicationController
  include IntegrationAccountScoped
  # Shops are owned by tessera-core (ADR-007); MerchantHub reads them via
  # Tessera::Shop. Core integration accounts via TesseraCoreClient; shop UI config is local (ADR-007).
  def index
    @shops = policy_scope(Tessera::Shop, policy_scope_class: ShopPolicy::Scope)
    authorize Tessera::Shop, :index?, policy_class: ShopPolicy
  end

  def show
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :show?, policy_class: ShopPolicy
    load_credentials_metadata
  end

  def new
    authorize Tessera::Shop, :new?, policy_class: ShopPolicy
  end

  def create
    authorize Tessera::Shop, :create?, policy_class: ShopPolicy
    authorize_merchant_for_create!

    if shop_create_params_incomplete?
      flash.now[:alert] = I18n.t("flash.shops.missing_fields")
      return render :new, status: :unprocessable_entity
    end

    result = ControlPlane::ShopProvisioner.create!(merchant_id: target_merchant_id, **shop_create_params)
    redirect_to shop_path(result["shop_id"]),
                notice: I18n.t("flash.shops.create_success", name: result["name"])
  rescue TesseraCoreClient::Error => e
    flash.now[:alert] = I18n.t("flash.shops.create_failed", message: e.message)
    render :new, status: :unprocessable_entity
  end

  def edit
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :edit?, policy_class: ShopPolicy
  end

  def update
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :update?, policy_class: ShopPolicy

    result = Shops::UpdateSettings.call(@shop, shop_update_params)
    if result.errors.none?
      redirect_to shop_path(@shop), notice: I18n.t("flash.shops.update_success")
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def authorize_merchant_for_create!
    merchant_id = target_merchant_id
    if merchant_id.blank?
      raise Pundit::NotAuthorizedError, "merchant required"
    end

    return if current_user.psp_admin?
    return if current_user.merchant_admin? && current_user.merchant_id == merchant_id

    raise Pundit::NotAuthorizedError, "wrong merchant"
  end

  def target_merchant_id
    if current_user.psp_admin?
      params.dig(:shop, :merchant_id).presence
    else
      current_user.merchant_id
    end
  end

  def shop_create_params_incomplete?
    shop_create_params[:name].blank? || shop_create_params[:country].blank?
  end

  def shop_create_params
    params.fetch(:shop, {}).permit(:name, :country, :notification_url).to_h.symbolize_keys
  end

  def shop_update_params
    params.fetch(:shop, {}).permit(:display_name, :notification_url, :test_mode)
  end

  def load_credentials_metadata
    @credentials = client.list_credentials(integration_account_id: integration_account_id_for(@shop))
  rescue TesseraCoreClient::Error => e
    @credentials = []
    @credentials_error = e.message
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
