# frozen_string_literal: true

# Onboarding a merchant is a PSP-admin operation. Headless policy — there is
# no persisted MerchantHub model class (merchant rows live in the shared merchants table, ADR-007).
class MerchantPolicy < ApplicationPolicy
  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end
end
