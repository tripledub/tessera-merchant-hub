# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end

  private

  def psp_admin?
    user.psp_admin?
  end

  def psp_role?
    user.psp_role?
  end

  def merchant_admin?
    user.merchant_admin?
  end

  def merchant_role?
    user.merchant_role?
  end

  # True when the record's shop belongs to the user's merchant.
  def own_shop?(record)
    user.accessible_shop_ids&.include?(record.shop_id)
  end
end
