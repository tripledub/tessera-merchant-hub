# frozen_string_literal: true

class KycDocumentPolicy < ApplicationPolicy
  def show?
    psp_role?
  end

  def create?
    psp_admin?
  end

  def destroy?
    psp_admin?
  end

  def retry?
    psp_admin?
  end

  def confirm_link?
    psp_admin?
  end

  def reject_link?
    psp_admin?
  end
end
