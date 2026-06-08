require "rails_helper"

RSpec.describe "Merchant onboarding", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_x") }

  let(:valid_params) do
    {
      merchant: { name: "Acme", company_name: "Acme Ltd", country: "GB" },
      shop: { name: "Acme UK", country: "GB" },
      admin: { email: "owner@acme.test" }
    }
  end

  def stub_core_integration_account_for_onboarding!
    stub_request(:post, %r{/internal/integration_accounts\z}).to_return do |request|
      body = JSON.parse(request.body)
      shop_id = body["merchant_hub_shop_id"]
      integration_account_id = "intacct_#{shop_id}"

      {
        status: 201,
        body: {
          id: integration_account_id,
          merchant_hub_merchant_id: body["merchant_hub_merchant_id"],
          merchant_hub_shop_id: shop_id
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end
  end

  describe "GET /merchants/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "renders the onboarding form" do
        get new_merchant_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "is forbidden" do
        get new_merchant_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get new_merchant_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST /merchants" do
    context "when psp_admin with valid params" do
      before { sign_in psp_admin }

      it "creates the merchant locally, provisions the core integration account, and invites the admin" do
        stub_core_integration_account_for_onboarding!

        expect do
          post merchants_path, params: valid_params
        end.to change(User, :count).by(1)
          .and change(Tessera::Merchant, :count).by(1)
          .and change(Tessera::Shop, :count).by(1)

        user = User.find_by(email: "owner@acme.test")
        expect(user).to be_merchant_admin
        expect(user.merchant_id).to be_present
        expect(Tessera::Merchant.find_by(merchant_id: user.merchant_id)).to be_present
        expect(a_request(:post, %r{/internal/integration_accounts})).to have_been_made
        expect(a_request(:post, %r{/v1/merchants})).not_to have_been_made
        expect(response).to redirect_to(authenticated_root_path)
      end

      it "sends the new admin a password-set email" do
        stub_core_integration_account_for_onboarding!
        expect do
          post merchants_path, params: valid_params
        end.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end

    context "when psp_admin and core returns an error" do
      before { sign_in psp_admin }

      it "does not create a user and surfaces the error" do
        stub_request(:post, %r{/internal/integration_accounts\z})
          .to_return(status: 422, body: { error: "invalid" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        expect do
          post merchants_path, params: valid_params
        end.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when psp_admin submits a blank email" do
      before { sign_in psp_admin }

      it "re-renders without calling core" do
        post merchants_path, params: valid_params.merge(admin: { email: "" })
        expect(response).to have_http_status(:unprocessable_content)
        expect(a_request(:post, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "is forbidden" do
        post merchants_path, params: valid_params
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
