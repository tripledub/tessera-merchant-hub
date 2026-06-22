# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentTags, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:presenter_class) do
    Class.new(BasePresenter) do
      include ContentTags
      presents :item
    end
  end
  let(:object) { instance_double(Applicant) }
  let(:presenter) { presenter_class.new(object, template) }

  describe "#badge" do
    it "renders a span with colour classes" do
      html = presenter.badge("Active", :green)
      expect(html).to include("Active")
      expect(html).to include("bg-green-50")
      expect(html).to include("text-green-700")
    end

    it "supports different colour schemes" do
      html = presenter.badge("Warning", :amber)
      expect(html).to include("bg-amber-50")
      expect(html).to include("text-amber-700")
    end
  end

  describe "#definition_row" do
    it "renders a dt/dd pair" do
      html = presenter.definition_row("Label", "Value")
      expect(html).to include("Label")
      expect(html).to include("Value")
      expect(html).to include("<dt")
      expect(html).to include("<dd")
    end
  end

  describe "#status_dot" do
    it "renders a coloured dot with label" do
      html = presenter.status_dot("Online", :green)
      expect(html).to include("Online")
      expect(html).to include("bg-green-500")
    end
  end
end
