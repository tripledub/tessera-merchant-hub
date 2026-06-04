# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Shop credentials", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  let_it_be(:own_shop) do
    create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc", integration_account_id: "intacct_abc",
      name: "Acme Store")
  end
  let_it_be(:other_shop) do
    create(:tessera_shop, merchant_id: "merch_xyz", shop_id: "shop_xyz", integration_account_id: "intacct_xyz",
      name: "Other Store")
  end

  let(:credential_response) do
    {
      "id" => "cred_1",
      "api_key" => "pk_live_123",
      "secret_key" => "sk_live_secret_123",
      "signing_secret" => "whsec_secret_123"
    }
  end

  describe "POST /shops/:shop_id/credential" do
    context "when merchant_admin generates credentials for their own shop" do
      before { sign_in merchant_admin }

      it "calls core and redirects to the show-once page" do
        stub_core_create_credential!(
          integration_account_id: own_shop.integration_account_id,
          response_body: credential_response
        )

        post shop_credential_path(own_shop)

        expect(response).to redirect_to(shop_credential_show_once_path(own_shop))
        expect(a_request(:post, %r{/internal/integration_accounts/#{own_shop.integration_account_id}/credentials}))
          .to have_been_made
      end

      it "does not persist secret material in MerchantHub tables" do
        stub_core_create_credential!(
          integration_account_id: own_shop.integration_account_id,
          response_body: credential_response
        )

        post shop_credential_path(own_shop)

        expect(User.where(email: "sk_live_secret_123")).not_to exist
        expect(Tessera::Shop.where(notification_url: "sk_live_secret_123")).not_to exist
        expect(Tessera::Shop.where(name: "whsec_secret_123")).not_to exist
      end
    end

    context "when merchant_admin targets another merchant's shop" do
      before { sign_in merchant_admin }

      it "is forbidden" do
        post shop_credential_path(other_shop)
        expect(response).to have_http_status(:forbidden)
        expect(a_request(:post, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "is forbidden" do
        post shop_credential_path(own_shop)
        expect(response).to have_http_status(:forbidden)
        expect(a_request(:post, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "is forbidden" do
        post shop_credential_path(own_shop)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "can generate credentials for any shop" do
        stub_core_create_credential!(
          integration_account_id: other_shop.integration_account_id,
          response_body: credential_response
        )

        post shop_credential_path(other_shop)

        expect(response).to redirect_to(shop_credential_show_once_path(other_shop))
      end
    end
  end

  describe "GET /shops/:shop_id/credentials/show_once" do
    before { sign_in merchant_admin }

    it "shows the secret key and signing secret exactly once" do
      stub_core_create_credential!(
        integration_account_id: own_shop.integration_account_id,
        response_body: credential_response
      )

      post shop_credential_path(own_shop)
      follow_redirect!

      expect(response.body).to include("pk_live_123")
      expect(response.body).to include("sk_live_secret_123")
      expect(response.body).to include("whsec_secret_123")
      expect(response.body).to include("shown exactly once")

      get shop_credential_show_once_path(own_shop)

      expect(response).to redirect_to(shop_path(own_shop))
      expect(response.body).not_to include("sk_live_secret_123")
      expect(response.body).not_to include("whsec_secret_123")
    end

    it "does not show secrets without a fresh generation result" do
      get shop_credential_show_once_path(own_shop)

      expect(response).to redirect_to(shop_path(own_shop))
      expect(response.body).not_to include("sk_live_secret_123")
    end
  end

  describe "DELETE /shops/:shop_id/credentials/:id" do
    context "when merchant_admin revokes a credential for their own shop" do
      before { sign_in merchant_admin }

      it "calls core and redirects to the shop" do
        stub_core_revoke_credential!(
          integration_account_id: own_shop.integration_account_id,
          credential_id: "cred_1",
          response_body: { "id" => "cred_1", "api_key" => "pk_live_123", "status" => "revoked" }
        )

        delete shop_credential_revoke_path(own_shop, "cred_1")

        expect(response).to redirect_to(shop_path(own_shop))
        expect(a_request(:delete, %r{/internal/integration_accounts/#{own_shop.integration_account_id}/credentials/cred_1}))
          .to have_been_made
      end
    end

    context "when merchant_admin targets another merchant's shop" do
      before { sign_in merchant_admin }

      it "is forbidden" do
        delete shop_credential_revoke_path(other_shop, "cred_1")
        expect(response).to have_http_status(:forbidden)
        expect(a_request(:delete, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "is forbidden" do
        delete shop_credential_revoke_path(own_shop, "cred_1")
        expect(response).to have_http_status(:forbidden)
        expect(a_request(:delete, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "can revoke credentials for any shop" do
        stub_core_revoke_credential!(
          integration_account_id: other_shop.integration_account_id,
          credential_id: "cred_1",
          response_body: { "id" => "cred_1", "api_key" => "pk_live_123", "status" => "revoked" }
        )

        delete shop_credential_revoke_path(other_shop, "cred_1")

        expect(response).to redirect_to(shop_path(other_shop))
      end
    end
  end
end
