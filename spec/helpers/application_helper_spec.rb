# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#present" do
    let(:user) { create(:applicant) }

    before do
      stub_const("ApplicantPresenter", Class.new(BasePresenter) {
        presents :applicant

        def formatted_name
          applicant.name.upcase
        end
      })
    end

    it "instantiates the correct presenter by convention" do
      presenter = helper.present(user)
      expect(presenter).to be_a(ApplicantPresenter)
    end

    it "yields the presenter when a block is given" do
      helper.present(user) do |p|
        expect(p).to be_a(ApplicantPresenter)
        expect(p.formatted_name).to eq(user.name.upcase)
      end
    end

    it "accepts an explicit presenter class" do
      custom_class = Class.new(BasePresenter) do
        presents :thing
      end

      presenter = helper.present(user, custom_class)
      expect(presenter).to be_a(custom_class)
    end

    it "returns the presenter" do
      result = helper.present(user)
      expect(result).to be_a(ApplicantPresenter)
    end
  end
end
