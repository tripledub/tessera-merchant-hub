class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show refund void]

  ALLOWED_PER_PAGE = [ 10, 25, 50 ].freeze
  SORTABLE_COLUMNS = %w[amount inserted_at status].freeze
  SORT_DIRECTIONS  = %w[asc desc].freeze
  private_constant :ALLOWED_PER_PAGE, :SORTABLE_COLUMNS, :SORT_DIRECTIONS

  def index
    scope = policy_scope(Tessera::Payment, policy_scope_class: PaymentPolicy::Scope)
    scope = apply_filters(scope)
    scope = apply_sort(scope)
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
      begin
        scope = scope.from_date(params[:date_from])
      rescue ArgumentError, Date::Error
        flash.now[:alert] = "Invalid 'from' date — filter not applied."
      end
    end
    if params[:date_to].present?
      begin
        scope = scope.to_date(params[:date_to])
      rescue ArgumentError, Date::Error
        flash.now[:alert] = "Invalid 'to' date — filter not applied."
      end
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

  # Applies URL-param-driven sort. Falls back to inserted_at desc for unknown/missing params.
  # SORTABLE_COLUMNS allowlist prevents SQL injection via column name.
  def apply_sort(scope)
    valid_col = SORTABLE_COLUMNS.include?(params[:sort])
    valid_dir = SORT_DIRECTIONS.include?(params[:direction])
    # Both column and direction must be valid; otherwise fall back to inserted_at desc.
    return scope.order(inserted_at: :desc) unless valid_col

    dir = valid_dir ? params[:direction].to_sym : :desc
    scope.order(params[:sort] => dir)
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
