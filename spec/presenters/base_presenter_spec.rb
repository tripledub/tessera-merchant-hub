# frozen_string_literal: true

require "rails_helper"

RSpec.describe BasePresenter, type: :presenter do
  let(:object) { instance_double(Applicant, name: "Test") }
  let(:template) { instance_double(ActionView::Base) }
  let(:presenter) { described_class.new(object, template) }

  describe "template delegation" do
    it "delegates unknown methods to the template" do
      allow(template).to receive(:link_to).and_return("<a>link</a>")

      expect(presenter.link_to("/")).to eq("<a>link</a>")
    end

    it "responds to template methods" do
      allow(template).to receive(:respond_to?).and_return(true)

      expect(presenter.respond_to?(:content_tag)).to be true
    end
  end

  describe ".presents" do
    let(:presenter_class) do
      Class.new(described_class) do
        presents :widget
      end
    end

    it "defines an accessor for the wrapped object" do
      p = presenter_class.new(object, template)
      expect(p.widget).to eq(object)
    end
  end
end
