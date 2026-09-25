# frozen_string_literal: true

module Synthetic
  class ScenarioPolicy < ApplicationPolicy
    def index? = psp_admin?
    def show?  = psp_admin?
    def download? = psp_admin?
  end
end
