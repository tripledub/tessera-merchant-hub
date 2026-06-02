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
      "pk" => "pk_live_123",
      "sk" => "sk_live_secret",
      "signing_secret" => "whsec_secret",
      "status" => "revoked",
      "created" => "2026-06-01T10:00:00Z",
      "last_used" => "2026-06-02T12:00:00Z",
      "signing_required" => true
    }
  end

  def stub_core_credentials_metadata!(shop_id, response_body: [])
    stub_request(:get, %r{/v1/shops/#{shop_id}/credentials\z})
      .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
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
        stub_core_credentials_metadata!(other_shop.shop_id)

        get shop_path(other_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Other Store")
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "shows a shop in their merchant" do
        stub_core_credentials_metadata!(own_shop.shop_id)

        get shop_path(own_shop)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Store")
      end

      it "lists credential public metadata without secret material" do
        stub_core_credentials_metadata!(
          own_shop.shop_id,
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
        stub_core_credentials_metadata!(own_shop.shop_id)

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
      stub_request(:post, %r{/v1/merchants/#{merchant_id}/shops\z}).to_return do |_request|
        create(:tessera_shop, merchant_id: merchant_id, shop_id: shop_id, name: name, country: country)
        {
          status: 201,
          body: { shop_id: shop_id, name: name, country: country }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      end
    end

    context "when merchant_admin with valid params" do
      before { sign_in merchant_admin }

      it "provisions the shop in core and redirects to it" do
        stub_core_create_shop!(merchant_id: "merch_abc")

        post shops_path, params: shop_params

        expect(response).to redirect_to(shop_path("shop_new"))
        expect(a_request(:post, %r{/v1/merchants/merch_abc/shops})).to have_been_made
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
        expect(response).to have_http_status(:unprocessable_entity)
        expect(a_request(:post, %r{/v1/merchants})).not_to have_been_made
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
        stub_core_create_shop!(merchant_id: "merch_xyz", shop_id: "shop_xyz")

        post shops_path, params: shop_params.merge(shop: shop_params[:shop].merge(merchant_id: "merch_xyz"))

        expect(response).to redirect_to(shop_path("shop_xyz"))
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
    def stub_core_update_shop!(shop_id:, body:)
      stub_request(:patch, %r{/v1/shops/#{shop_id}\z}).to_return do |_request|
        conn = ActiveRecord::Base.connection
        conn.execute(<<~SQL.squish)
          UPDATE shops
          SET notification_url = #{conn.quote(body[:notification_url])},
              test_mode = #{body[:test_mode] ? 'TRUE' : 'FALSE'}
          WHERE shop_id = #{conn.quote(shop_id)}
        SQL
        { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
      end
    end

    context "when merchant_admin updates own shop" do
      before { sign_in merchant_admin }

      it "calls core and redirects" do
        stub_core_update_shop!(
          shop_id: own_shop.shop_id,
          body: { shop_id: own_shop.shop_id, notification_url: "https://new.test/hook", test_mode: true }
        )

        patch shop_path(own_shop), params: {
          shop: { notification_url: "https://new.test/hook", test_mode: "1" }
        }

        expect(response).to redirect_to(shop_path(own_shop))
        expect(a_request(:patch, %r{/v1/shops/#{own_shop.shop_id}})).to have_been_made
      end

      it "shows updated config on the shop page" do
        stub_core_update_shop!(
          shop_id: own_shop.shop_id,
          body: { shop_id: own_shop.shop_id, notification_url: "https://new.test/hook", test_mode: true }
        )

        patch shop_path(own_shop), params: {
          shop: { notification_url: "https://new.test/hook", test_mode: "1" }
        }
        stub_core_credentials_metadata!(own_shop.shop_id)
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
        expect(a_request(:patch, %r{/v1/shops})).not_to have_been_made
      end
    end

    context "when core returns an error" do
      before { sign_in merchant_admin }

      it "re-renders edit" do
        stub_request(:patch, %r{/v1/shops/#{own_shop.shop_id}})
          .to_return(status: 422, body: { error: "invalid" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        patch shop_path(own_shop), params: { shop: { notification_url: "https://new.test/hook" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
