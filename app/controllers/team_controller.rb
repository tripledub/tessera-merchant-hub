# frozen_string_literal: true

class TeamController < ApplicationController
  expose(:team_members) {
    policy_scope(User, policy_scope_class: UserPolicy::Scope).order(:email)
  }

  def index
    authorize User, :index?, policy_class: UserPolicy
  end

  def new
    authorize User, :invite?, policy_class: UserPolicy
  end

  def create
    authorize User, :invite?, policy_class: UserPolicy
    permitted = invite_params
    # Guard against role injection: this UI is merchant-only; the service also
    # accepts psp_* roles for the admin controller, so we validate here too.
    unless %w[merchant_admin merchant_viewer].include?(permitted[:role])
      flash.now[:alert] = t("flash.team.invalid_role")
      return render :new, status: :unprocessable_content
    end
    result = Users::Invite.call(permitted.merge(merchant_id: current_user.merchant_id))
    if result.errors.none?
      redirect_to team_index_path, notice: t("flash.team.invite_success", email: result.email)
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    authorize User, :deactivate_role?, policy_class: UserPolicy
    member = policy_scope(User, policy_scope_class: UserPolicy::Scope).find(params[:id])
    authorize member, :deactivate?, policy_class: UserPolicy
    result = Users::Deactivate.call(member, current_user)
    if result.errors.none?
      redirect_to team_index_path, notice: t("flash.team.deactivate_success", email: member.email)
    else
      redirect_to team_index_path, alert: result.errors.full_messages.to_sentence
    end
  end

  private

  def invite_params
    params.fetch(:user, {}).permit(:email, :role)
  end
end
