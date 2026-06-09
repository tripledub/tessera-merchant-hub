# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  expose(:users) {
    scope = policy_scope(User, policy_scope_class: UserPolicy::Scope)
    scope = scope.where(role: params[:role]) if params[:role].present?
    scope = scope.where(merchant_id: params[:merchant_id]) if params[:merchant_id].present?
    scope.order(:email)
  }

  def index
    authorize User, :admin_index?, policy_class: UserPolicy
    @pagy, @users = pagy(:offset, users)
  end

  def new
    authorize User, :admin_invite?, policy_class: UserPolicy
  end

  def create
    authorize User, :admin_invite?, policy_class: UserPolicy
    result = Users::Invite.call(invite_params)
    if result.errors.none?
      redirect_to admin_users_path, notice: t("flash.admin.users.invite_success", email: result.email)
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def unlock
    member = User.find(params[:id])
    authorize member, :unlock?, policy_class: UserPolicy
    member.unlock_access!
    member.update!(deactivated_at: nil) if member.reload.deactivated?
    redirect_to admin_users_path, notice: t("flash.admin.users.unlock_success", email: member.email)
  end

  def update_role
    member = User.find(params[:id])
    authorize member, :update_role?, policy_class: UserPolicy
    # psp_admin can assign any valid role, including cross-tier promotions.
    # The policy gate (update_role? → psp_admin? only) is the sole constraint by design.
    if member.update(role_params)
      redirect_to admin_users_path, notice: t("flash.admin.users.role_updated", email: member.email)
    else
      redirect_to admin_users_path, alert: member.errors.full_messages.to_sentence
    end
  end

  private

  def invite_params
    params.fetch(:user, {}).permit(:email, :role)
  end

  def role_params
    params.fetch(:user, {}).permit(:role)
  end
end
