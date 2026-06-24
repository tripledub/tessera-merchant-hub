# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigationHelper, type: :helper do
  describe "#nav_link_to" do
    before do
      allow(helper).to receive(:controller_name).and_return("payments")
    end

    context "when the current controller matches" do
      it "applies menu-item-active class" do
        html = helper.nav_link_to("Payments", "/payments", controller: "payments")

        expect(html).to include("menu-item-active")
        expect(html).not_to include("menu-item-inactive")
      end

      it "sets aria-current to page" do
        html = helper.nav_link_to("Payments", "/payments", controller: "payments")

        expect(html).to include('aria-current="page"')
      end
    end

    context "when the current controller does not match" do
      it "applies menu-item-inactive class" do
        html = helper.nav_link_to("Shops", "/shops", controller: "shops")

        expect(html).to include("menu-item-inactive")
        expect(html).not_to include("menu-item-active")
      end

      it "does not set aria-current" do
        html = helper.nav_link_to("Shops", "/shops", controller: "shops")

        expect(html).not_to include("aria-current")
      end
    end

    it "renders the label inside a menu-item-text span" do
      html = helper.nav_link_to("Dashboard", "/", controller: "dashboard")

      expect(html).to include("<span")
      expect(html).to include("menu-item-text")
      expect(html).to include("Dashboard")
    end

    context "when an icon is provided" do
      it "renders the icon partial" do
        allow(helper).to receive(:render).with("shared/icons/home").and_return("icon-svg".html_safe)

        html = helper.nav_link_to("Home", "/", controller: "home", icon: "home")

        expect(html).to include("icon-svg")
      end

      it "handles missing icon partials gracefully" do
        allow(helper).to receive(:render).with("shared/icons/missing").and_raise(
          ActionView::MissingTemplate.new([], "shared/icons/missing", [], false, "")
        )

        html = helper.nav_link_to("Home", "/", controller: "home", icon: "missing")

        expect(html).to include("Home")
      end
    end
  end
end
