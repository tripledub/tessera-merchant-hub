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

  def stub_core_success(merchant_id: "merch_new")
    stub_request(:post, %r{/v1/merchants\z})
      .to_return(status: 201, body: { merchant_id: merchant_id, name: "Acme" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{/v1/merchants/.+/shops\z})
      .to_return(status: 201, body: { shop_id: "shop_new", name: "Acme UK" }.to_json,
                 headers: { "Content-Type" => "application/json" })
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

      it "provisions merchant + shop in core and creates the first merchant_admin" do
        stub_core_success(merchant_id: "merch_new")

        expect do
          post merchants_path, params: valid_params
        end.to change(User, :count).by(1)

        user = User.find_by(email: "owner@acme.test")
        expect(user).to be_merchant_admin
        expect(user.merchant_id).to eq("merch_new")
        expect(response).to redirect_to(authenticated_root_path)
      end

      it "sends the new admin a password-set email" do
        stub_core_success
        expect do
          post merchants_path, params: valid_params
        end.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end

    context "when psp_admin and core returns an error" do
      before { sign_in psp_admin }

      it "does not create a user and surfaces the error" do
        stub_request(:post, %r{/v1/merchants\z})
          .to_return(status: 422, body: { error: "invalid" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        expect do
          post merchants_path, params: valid_params
        end.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when psp_admin submits a blank email" do
      before { sign_in psp_admin }

      it "re-renders without calling core" do
        post merchants_path, params: valid_params.merge(admin: { email: "" })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(a_request(:post, %r{/v1/merchants})).not_to have_been_made
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
