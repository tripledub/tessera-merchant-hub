# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Deactivate do
  let(:actor)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let(:target) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  def call(user = target, acting_as = actor)
    described_class.call(user, acting_as)
  end

  describe ".call" do
    it "sets deactivated_at on the target user" do
      freeze_time do
        call
        expect(target.reload.deactivated_at).to eq(Time.current)
      end
    end

    it "locks the target user via Devise (sets locked_at)" do
      call
      expect(target.reload.locked_at).not_to be_nil
    end

    it "returns the user" do
      result = call
      expect(result).to eq(target)
    end

    it "returns user with error when actor tries to deactivate themselves" do
      result = call(actor, actor)
      expect(result.errors[:base]).to include("You cannot deactivate your own account")
    end

    it "does not set deactivated_at when self-deactivation attempted" do
      call(actor, actor)
      expect(actor.reload.deactivated_at).to be_nil
    end

    context "when lock_access! raises after update!" do
      it "rolls back deactivated_at so the user record is not in a partial state" do
        allow(target).to receive(:lock_access!).and_raise(ActiveRecord::RecordInvalid.new(target))

        result = call
        expect(target.reload.deactivated_at).to be_nil
        expect(result.errors[:base]).not_to be_empty
      end
    end
  end
end
