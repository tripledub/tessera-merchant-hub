# frozen_string_literal: true

class DomainBlocklistEntryPolicy < ApplicationPolicy
  def index?   = psp_admin?
  def create?  = psp_admin?
  def destroy? = psp_admin?
end
