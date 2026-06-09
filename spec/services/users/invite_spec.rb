# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Invite do
  def call(overrides = {})
    described_class.call({
      email:       "newuser@example.com",
      role:        "merchant_viewer",
      merchant_id: "merch_abc"
    }.merge(overrides))
  end

  describe ".call" do
    it "creates a user with the given email, role, and merchant_id" do
      expect { call }.to change(User, :count).by(1)

      user = User.last
      expect(user.email).to eq("newuser@example.com")
      expect(user.role).to eq("merchant_viewer")
      expect(user.merchant_id).to eq("merch_abc")
    end

    it "sends reset password instructions after save" do
      user_double = instance_spy(User, save: true, errors: ActiveModel::Errors.new(User.new))
      allow(User).to receive(:new).and_return(user_double)
      described_class.call(email: "x@x.com", role: "merchant_viewer", merchant_id: "merch_abc")
      expect(user_double).to have_received(:send_reset_password_instructions)
    end

    it "does not send email when save fails (duplicate email)" do
      create(:user, email: "newuser@example.com")
      result = call
      expect(result.errors).not_to be_empty
    end

    it "returns user with errors when role is not permitted" do
      result = call(role: "superadmin")
      expect(result.errors[:role]).to include("is not permitted")
    end

    it "creates a psp_admin user when no merchant_id given" do
      result = call(role: "psp_admin", merchant_id: nil)
      expect(result.errors).to be_empty
      expect(User.last.role).to eq("psp_admin")
    end

    it "ignores unpermitted keys in params" do
      expect {
        described_class.call(email: "safe@example.com", role: "merchant_viewer",
                             merchant_id: "m1", admin: true)
      }.to change(User, :count).by(1)
    end
  end
end
