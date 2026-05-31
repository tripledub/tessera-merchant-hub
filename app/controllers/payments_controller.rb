class PaymentsController < ApplicationController
  def index
    scope = policy_scope(Tessera::Payment, policy_scope_class: PaymentPolicy::Scope)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.order(inserted_at: :desc)
    @pagy, @payments = pagy(scope, limit: 50)
    authorize Tessera::Payment, :index?, policy_class: PaymentPolicy
  end

  def show
    @payment = Tessera::Payment.find(params[:id])
    authorize @payment, :show?, policy_class: PaymentPolicy
  end
end
