class ShopsController < ApplicationController
  # Shops are owned by tessera-core (ADR-007); MerchantHub reads them via
  # Tessera::Shop. Provisioning and config changes go through TesseraCoreClient.
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
      flash.now[:alert] = "Shop name and territory (country) are required."
      return render :new, status: :unprocessable_entity
    end

    result = client.create_shop(merchant_id: target_merchant_id, **shop_create_params)
    redirect_to shop_path(result["shop_id"]),
                notice: "Shop #{result['name']} created."
  rescue TesseraCoreClient::Error => e
    flash.now[:alert] = "Could not create shop: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def edit
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :edit?, policy_class: ShopPolicy
  end

  def update
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :update?, policy_class: ShopPolicy

    client.update_shop(shop_id: @shop.shop_id, **shop_update_params)
    redirect_to shop_path(@shop), notice: "Shop configuration updated."
  rescue TesseraCoreClient::Error => e
    flash.now[:alert] = "Could not update shop: #{e.message}"
    render :edit, status: :unprocessable_entity
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
    permitted = params.fetch(:shop, {}).permit(:notification_url, :test_mode)
    attrs = permitted.to_h.symbolize_keys
    attrs[:test_mode] = ActiveModel::Type::Boolean.new.cast(attrs[:test_mode]) if attrs.key?(:test_mode)
    attrs
  end

  def load_credentials_metadata
    @credentials = client.list_credentials(shop_id: @shop.shop_id)
  rescue TesseraCoreClient::Error => e
    @credentials = []
    @credentials_error = e.message
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
