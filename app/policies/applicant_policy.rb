# frozen_string_literal: true

class ApplicantPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

  def show?
    psp_role?
  end

  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end

  def edit?
    psp_admin?
  end

  def update?
    psp_admin?
  end

  def destroy?
    psp_admin?
  end

  def run_extraction?
    psp_admin?
  end

  # MH-251: confirming (or removing) "this applicant has no corporate owners"
  # is a compliance judgement, so it sits with psp_admin.
  def attest_no_corporate_owners?
    psp_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?

      scope.none
    end
  end
end
