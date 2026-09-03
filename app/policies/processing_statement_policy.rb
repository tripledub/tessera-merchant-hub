# frozen_string_literal: true

class ProcessingStatementPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

  def show?
    psp_role?
  end

  def create?
    psp_admin?
  end

  def update?
    psp_admin? && record.mappable?
  end

  def destroy?
    psp_admin? && record.removable?
  end

  def recover?
    psp_admin?
  end

  # Only a fully processed statement has real metrics — exporting one
  # that's still queued, mapped, or errored would produce a blank or
  # empty-looking CSV that reads as a legitimate (but wrong) report.
  def export?
    psp_role? && record.processed?
  end
end
