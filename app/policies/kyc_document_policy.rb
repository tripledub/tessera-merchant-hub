# frozen_string_literal: true

class KycDocumentPolicy < ApplicationPolicy
  def show?
    psp_role?
  end

  def create?
    psp_admin?
  end

  def confirm_match?
    psp_admin?
  end

  def reject_match?
    psp_admin?
  end
end
