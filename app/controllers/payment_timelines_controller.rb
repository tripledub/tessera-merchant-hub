class PaymentTimelinesController < ApplicationController
  # Internal system event types hidden from merchant roles
  MERCHANT_HIDDEN_ACTORS = %w[system].freeze

  def show
    @payment = Tessera::Payment.find(params[:payment_id])
    authorize @payment, :show?, policy_class: PaymentPolicy

    events = @payment.audit_events.chronological
    events = events.where.not(actor: MERCHANT_HIDDEN_ACTORS) if current_user.merchant_role?

    @audit_events     = events
    @webhook_deliveries = @payment.webhook_deliveries.order(last_attempted_at: :desc)
  end
end
