require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user, password: "password123!") }

  describe "POST /users/sign_in" do
    it "signs in with valid credentials" do
      post user_session_path, params: { user: { email: user.email, password: "password123!" } }
      expect(response).to redirect_to(root_path)
    end

    it "rejects invalid credentials" do
      post user_session_path, params: { user: { email: user.email, password: "wrong" } }
      expect(response.body).to include("Invalid email or password")
    end

    it "locks the account after too many failed attempts" do
      Devise.maximum_attempts.times do
        post user_session_path, params: { user: { email: user.email, password: "wrong" } }
      end
      expect(user.reload).to be_access_locked
    end
  end

  describe "DELETE /users/sign_out" do
    it "signs out a signed-in user" do
      sign_in user
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end
end
