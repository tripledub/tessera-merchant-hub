# frozen_string_literal: true

# Onboarding a merchant is a PSP-admin operation. Headless policy — there is
# no persisted MerchantHub record (merchants live in tessera-core, ADR-007).
class MerchantPolicy < ApplicationPolicy
  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end
end
