class ShopsController < ApplicationController
  # Shops are owned by tessera-core (ADR-007); MerchantHub reads them via
  # Tessera::Shop. Editing shop config goes through the core API (MH-21).
  def index
    @shops = policy_scope(Tessera::Shop, policy_scope_class: ShopPolicy::Scope)
    authorize Tessera::Shop, :index?, policy_class: ShopPolicy
  end

  def show
    @shop = Tessera::Shop.find_by!(shop_id: params[:id])
    authorize @shop, :show?, policy_class: ShopPolicy
  end
end
