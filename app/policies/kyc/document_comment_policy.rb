# frozen_string_literal: true

module Kyc
  class DocumentCommentPolicy < ApplicationPolicy
    def index?
      psp_role?
    end

    def create?
      psp_role?
    end
  end
end
