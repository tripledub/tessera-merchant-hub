# frozen_string_literal: true

module Users
  class Deactivate
    def self.call(user, actor) = new(user, actor).call

    def initialize(user, actor)
      @user  = user
      @actor = actor
    end

    def call
      if @user == @actor
        @user.errors.add(:base, "You cannot deactivate your own account")
        return @user
      end

      @user.update!(deactivated_at: Time.current)
      @user.lock_access!(send_instructions: false)
      @user
    end
  end
end
