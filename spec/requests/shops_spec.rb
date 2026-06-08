require "rails_helper"

RSpec.describe "Shops", type: :request do
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:psp_support)     { create(:user, :psp_support) }
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  let_it_be(:own_shop)   { create(:tessera_shop, merchant_id: "merch_abc", shop_id: "shop_abc", name: "Acme Store") }
  let_it_be(:other_shop) { create(:tessera_shop, merchant_id: "merch_xyz", shop_id: "shop_xyz", name: "Other Store") }

  let(:credential_metadata) do
    {
      "id" => "cred_1",
      "api_key" => "pk_live_123",
      "status" => "revoked",
      "created_at" => "2026-06-01T10:00:00Z",
      "last_used_at" => "2026-06-02T12:00:00Z",
      "signing_required" => true
    }
  end

  def stub_core_credentials_metadata!(shop, response_body: [])
    stub_core_list_credentials!(integration_account_id: shop.integration_account_id, response_body: response_body)
  end

  describe "GET /shops" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
        expect(response.body).to include("Other Store")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200 and lists all shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "lists only the merchant's own shops" do
        get shops_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
        expect(response.body).not_to include("Other Store")
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get shops_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /shops/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows any shop" do
        stub_core_credentials_metadata!(other_shop)

        get shop_path(other_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Other Store")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "shows a shop in their merchant" do
        stub_core_credentials_metadata!(own_shop)

        get shop_path(own_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end

      it "lists credential public metadata without secret material" do
        stub_core_credentials_metadata!(
          own_shop,
          response_body: [ credential_metadata ]
        )

        get shop_path(own_shop)

        expect(response.body).to include("pk_live_123")
        expect(response.body).to include("Revoked")
        expect(response.body).to include("2026-06-01T10:00:00Z")
        expect(response.body).to include("2026-06-02T12:00:00Z")
        expect(response.body).not_to include("sk_live_secret")
        expect(response.body).not_to include("whsec_secret")
      end

      it "returns 403 for another merchant's shop" do
        get shop_path(other_shop)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "shows a shop in their merchant" do
        stub_core_credentials_metadata!(own_shop)

        get shop_path(own_shop)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /shops/new" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "renders the form" do
        get new_shop_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "is forbidden" do
        get new_shop_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /shops" do
    let(:shop_params) do
      { shop: { name: "Acme EU", country: "DE", notification_url: "https://acme.test/hook" } }
    end

    def stub_core_create_shop!(merchant_id:, shop_id: "shop_new", name: "Acme EU", country: "DE")
      stub_core_create_integration_account!(
        merchant_id: merchant_id,
        shop_id: shop_id,
        name: name,
        country: country
      )
    end

    context "when merchant_admin with valid params" do
      before { sign_in merchant_admin }

      it "provisions the shop in core and redirects to it" do
        stub_core_create_shop!(merchant_id: "merch_abc")

        expect do
          post shops_path, params: shop_params
        end.to change(Tessera::Shop, :count).by(1)

        created = Tessera::Shop.order(created_at: :desc).first
        expect(response).to redirect_to(shop_path(created.shop_id))
        expect(a_request(:post, %r{/internal/integration_accounts})).to have_been_made
      end

      it "shows the new shop in the index" do
        stub_core_create_shop!(merchant_id: "merch_abc")

        post shops_path, params: shop_params
        get shops_path

        expect(response.body).to include("Acme EU")
        expect(response.body).to include("DE")
      end
    end

    context "when merchant_admin submits incomplete params" do
      before { sign_in merchant_admin }

      it "re-renders without calling core" do
        post shops_path, params: { shop: { name: "", country: "" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(a_request(:post, %r{/internal/integration_accounts})).not_to have_been_made
      end
    end

    context "when psp_admin without merchant_id" do
      before { sign_in psp_admin }

      it "is forbidden" do
        post shops_path, params: shop_params
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates a shop for the given merchant" do
        stub_core_create_shop!(merchant_id: "merch_xyz")

        expect do
          post shops_path, params: shop_params.merge(shop: shop_params[:shop].merge(merchant_id: "merch_xyz"))
        end.to change { Tessera::Shop.where(merchant_id: "merch_xyz").count }.by(1)

        created = Tessera::Shop.where(merchant_id: "merch_xyz").order(created_at: :desc).first
        expect(response).to redirect_to(shop_path(created.shop_id))
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "is forbidden" do
        post shops_path, params: shop_params
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /shops/:id/edit" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "renders for own shop" do
        get edit_shop_path(own_shop)
        expect(response).to have_http_status(:ok)
      end

      it "returns 403 for another merchant's shop" do
        get edit_shop_path(other_shop)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /shops/:id" do
    def apply_local_shop_config!(shop_id:, body:)
      conn = ActiveRecord::Base.connection
      conn.execute(<<~SQL.squish)
        UPDATE shops
        SET notification_url = #{conn.quote(body[:notification_url])},
            test_mode = #{body[:test_mode] ? 'TRUE' : 'FALSE'}
        WHERE shop_id = #{conn.quote(shop_id)}
      SQL
    end

    context "when merchant_admin updates own shop" do
      before { sign_in merchant_admin }

      it "updates local shop config and redirects" do
        patch shop_path(own_shop), params: {
          shop: { notification_url: "https://new.test/hook", test_mode: "1" }
        }

        expect(response).to redirect_to(shop_path(own_shop))
        expect(a_request(:patch, %r{/internal/})).not_to have_been_made
      end

      it "updates display_name and redirects" do
        patch shop_path(own_shop), params: {
          shop: { display_name: "Flagship Store" }
        }
        expect(response).to redirect_to(shop_path(own_shop))
        expect(own_shop.reload.display_name).to eq("Flagship Store")
      end

      it "shows updated config on the shop page" do
        patch shop_path(own_shop), params: {
          shop: { notification_url: "https://new.test/hook", test_mode: "1" }
        }
        stub_core_credentials_metadata!(own_shop)
        follow_redirect!
        get shop_path(own_shop)

        expect(response.body).to include("https://new.test/hook")
        expect(response.body).to include("Test")
      end
    end

    context "when merchant_admin updates another merchant's shop" do
      before { sign_in merchant_admin }

      it "is forbidden" do
        patch shop_path(other_shop), params: { shop: { notification_url: "https://evil.test/hook" } }
        expect(response).to have_http_status(:forbidden)
        expect(a_request(:patch, %r{/internal/})).not_to have_been_made
      end
    end

    context "when notification_url is not HTTPS" do
      before { sign_in merchant_admin }

      it "re-renders edit with 422" do
        patch shop_path(own_shop), params: {
          shop: { notification_url: "http://insecure.com/hook" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
