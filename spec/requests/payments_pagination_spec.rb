require "rails_helper"

RSpec.describe "Payments pagination", type: :request do
  let(:psp_admin) { create(:user, :psp_admin) }

  before { sign_in psp_admin }

  context "with more than one page of payments" do
    before do
      # 55 payments → 2 pages at limit 50
      55.times { create(:tessera_payment, shop_id: "shop_demo", status: "succeeded") }
    end

    it "renders the first page with a pagination nav" do
      get payments_path
      expect(response).to have_http_status(:ok)
      # Pagy v43 series_nav renders a nav element with a link to page 2
      expect(response.body).to include("page=2")
    end

    it "renders the second page" do
      get payments_path(page: 2)
      expect(response).to have_http_status(:ok)
      # A link back to page 1 should be present
      expect(response.body).to include("page=1")
    end

    it "handles an out-of-range page without erroring (overflow safety)" do
      get payments_path(page: 999)
      expect(response).to have_http_status(:ok)
    end
  end

  context "with a single page of payments" do
    before { 3.times { create(:tessera_payment, shop_id: "shop_demo") } }

    it "does not render pagination nav" do
      get payments_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("page=2")
    end
  end
end
