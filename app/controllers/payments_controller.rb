class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show refund void]

  ALLOWED_PER_PAGE = [10, 25, 50].freeze
  private_constant :ALLOWED_PER_PAGE

  def index
    scope = policy_scope(Tessera::Payment, policy_scope_class: PaymentPolicy::Scope)
    scope = apply_filters(scope)
    scope = scope.order(inserted_at: :desc)
    @pagy, @payments = pagy(:offset, scope, limit: per_page_value)
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

  def apply_filters(scope)
    scope = scope.with_statuses(params[:status])        if params[:status].present?
    if params[:date_from].present?
      scope = scope.from_date(params[:date_from]) rescue scope
    end
    if params[:date_to].present?
      scope = scope.to_date(params[:date_to]) rescue scope
    end
    scope = scope.with_reference(params[:reference])    if params[:reference].present?
    if params[:amount_min].present?
      scope = scope.amount_at_least((params[:amount_min].to_f * 100).round)
    end
    if params[:amount_max].present?
      scope = scope.amount_at_most((params[:amount_max].to_f * 100).round)
    end
    scope
  end

  def per_page_value
    requested = params[:per_page].to_i
    ALLOWED_PER_PAGE.include?(requested) ? requested : 25
  end

  def set_payment
    @payment = Tessera::Payment.find(params[:id])
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
