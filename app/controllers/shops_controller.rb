class ShopsController < ApplicationController
  before_action :set_shop, only: %i[show edit update]

  def index
    @shops = policy_scope(Shop)
    authorize Shop
  end

  def show
    authorize @shop
  end

  def edit
    authorize @shop
  end

  def update
    authorize @shop
    if @shop.update(shop_params)
      redirect_to shop_path(@shop), notice: "Shop updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_shop
    @shop = Shop.find(params[:id])
  end

  def shop_params
    params.require(:shop).permit(:notification_url, :test_mode)
  end
end
