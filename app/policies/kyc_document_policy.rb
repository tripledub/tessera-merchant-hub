# frozen_string_literal: true

class KycDocumentPolicy < ApplicationPolicy
  def show?
    psp_role?
  end

  def create?
    psp_admin?
  end
end
