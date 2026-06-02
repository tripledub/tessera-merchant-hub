require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def load_seeds
    load Rails.root.join("db/seeds.rb")
  end

  it "creates demo users for each role idempotently" do
    expect { load_seeds }.to change(User, :count).by(4)
    expect { load_seeds }.not_to change(User, :count)

    expect(User.find_by!(email: "psp-admin@tessera.test")).to be_psp_admin
    expect(User.find_by!(email: "psp-support@tessera.test")).to be_psp_support

    merchant_admin = User.find_by!(email: "merchant-admin@tessera.test")
    merchant_viewer = User.find_by!(email: "merchant-viewer@tessera.test")

    expect(merchant_admin).to be_merchant_admin
    expect(merchant_admin.merchant_id).to eq("merch_demo")
    expect(merchant_viewer).to be_merchant_viewer
    expect(merchant_viewer.merchant_id).to eq("merch_demo")
  end

  it "does not seed core-owned shop data" do
    expect { load_seeds }.not_to change(Tessera::Shop, :count)
  end
end
