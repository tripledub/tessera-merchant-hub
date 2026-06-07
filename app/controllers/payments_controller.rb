class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show refund void]

  def index
    scope = policy_scope(Tessera::Payment, policy_scope_class: PaymentPolicy::Scope)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.order(inserted_at: :desc)
    @pagy, @payments = pagy(:offset, scope, limit: 25)
    authorize Tessera::Payment, :index?, policy_class: PaymentPolicy
  end

  def show
    authorize @payment, :show?, policy_class: PaymentPolicy
  end

  def refund
    authorize @payment, :refund?, policy_class: PaymentPolicy
    client.post_refund(
      shop_id:    @payment.shop_id,
      payment_id: @payment.id,
      amount:     params[:amount].to_i,
      currency:   @payment.currency
    )
    redirect_to payment_path(@payment.id), notice: "Refund submitted successfully."
  rescue TesseraCoreClient::Error => e
    redirect_to payment_path(@payment.id), alert: "Refund failed: #{e.message}"
  end

  def void
    authorize @payment, :void?, policy_class: PaymentPolicy
    client.post_void(shop_id: @payment.shop_id, payment_id: @payment.id)
    redirect_to payment_path(@payment.id), notice: "Payment voided successfully."
  rescue TesseraCoreClient::Error => e
    redirect_to payment_path(@payment.id), alert: "Void failed: #{e.message}"
  end

  private

  def set_payment
    @payment = Tessera::Payment.find(params[:id])
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
