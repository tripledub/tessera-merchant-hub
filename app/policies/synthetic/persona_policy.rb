# frozen_string_literal: true

module Synthetic
  class PersonaPolicy < ApplicationPolicy
    def index? = psp_admin?
    def show?  = psp_admin?
    def new?   = psp_admin?
    def create? = psp_admin?
    def export? = psp_admin?
    def generate_document? = psp_admin?
  end
end
