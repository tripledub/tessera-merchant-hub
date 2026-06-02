# frozen_string_literal: true

class ShopCredentialsController < ApplicationController
  SESSION_KEY = :credential_show_once

  def create
    @shop = Tessera::Shop.find_by!(shop_id: params[:shop_id])
    authorize @shop, :generate_credential?, policy_class: ShopPolicy

    result = client.create_credential(shop_id: @shop.shop_id)
    session[SESSION_KEY] = {
      "shop_id" => @shop.shop_id,
      "pk" => result["pk"],
      "sk" => result["sk"],
      "signing_secret" => result["signing_secret"]
    }

    redirect_to shop_credential_show_once_path(@shop)
  rescue TesseraCoreClient::Error => e
    redirect_to shop_path(@shop), alert: "Could not generate credentials: #{e.message}"
  end

  def show_once
    @shop = Tessera::Shop.find_by!(shop_id: params[:shop_id])
    authorize @shop, :generate_credential?, policy_class: ShopPolicy

    payload = session.delete(SESSION_KEY)
    unless show_once_payload_valid?(payload)
      redirect_to shop_path(@shop),
                  alert: "Credential secrets are only shown once, immediately after generation."
      return
    end

    @credential = payload
  end

  private

  def show_once_payload_valid?(payload)
    payload.is_a?(Hash) &&
      payload["shop_id"] == @shop.shop_id &&
      payload["sk"].present? &&
      payload["signing_secret"].present?
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
