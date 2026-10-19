# frozen_string_literal: true

require "rails_helper"

# MH-399: chips are tied to the session state (what is still missing, who spoke
# last), never to what the assistant's message happens to say.
RSpec.describe Onboarding::QuickReplies do
  let(:applicant) { create(:applicant, company_name: nil) }
  let(:company_info_without_country) do
    {
      "company_info" => {
        "company_name" => "Acme Widgets Ltd",
        "registration_number" => "12345678",
        "company_type" => "limited_company",
        "registered_address" => "1 High Street, London"
      }
    }
  end
  let(:stage_data) { company_info_without_country }
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :company_info, stage_data: stage_data)
  end

  def say(role, content = "…")
    create(:onboarding_message, onboarding_session: session, role: role, content: content)
  end

  describe ".for" do
    context "when the country is the only company detail still missing and the assistant spoke last" do
      before { say(:bot, "Which country is the company registered in?") }

      it "offers the three target countries and Other, in that order" do
        options = described_class.for(session)

        expect(options.map(&:key)).to eq(%i[united_kingdom malta cyprus other])
        expect(options.map(&:label)).to eq([ "United Kingdom", "Malta", "Cyprus", "Other" ])
      end

      it "marks the countries as answers and Other as a prompt to type" do
        options = described_class.for(session)

        expect(options.first(3).map(&:kind)).to all(eq(:answer))
        expect(options.last.kind).to eq(:other)
      end

      it "does not depend on the wording of the assistant's message" do
        say(:bot, "Thanks! One last thing for your company details.")

        expect(described_class.for(session).map(&:key)).to eq(%i[united_kingdom malta cyprus other])
      end
    end

    it "offers nothing when other company details are still missing" do
      session.update!(stage_data: { "company_info" => { "company_name" => "Acme Widgets Ltd" } })
      say(:bot, "What is your registration number, type, address and country?")

      expect(described_class.for(session)).to be_empty
    end

    it "offers nothing once the country has been answered" do
      session.update!(stage_data: company_info_without_country.deep_merge(
        "company_info" => { "country_of_incorporation" => "United Kingdom" }
      ))
      say(:bot, "Thanks, that's everything.")

      expect(described_class.for(session)).to be_empty
    end

    it "offers nothing while the applicant's own message is the latest (a reply is in flight)" do
      say(:bot, "Which country is the company registered in?")
      say(:applicant, "United Kingdom")

      expect(described_class.for(session)).to be_empty
    end

    it "offers chips again if the reply did not capture the country and the assistant asks again" do
      say(:bot, "Which country is the company registered in?")
      say(:applicant, "somewhere nice")
      say(:bot, "Sorry, which country is the company registered in?")

      expect(described_class.for(session).map(&:key)).to eq(%i[united_kingdom malta cyprus other])
    end

    it "offers nothing in a later stage, even if a country is somehow missing" do
      session.update!(current_stage: :directors_ubos, stage_data: company_info_without_country)
      say(:bot, "Who are the directors?")

      expect(described_class.for(session)).to be_empty
    end

    it "offers nothing before the conversation has started" do
      expect(described_class.for(session)).to be_empty
    end

    it "offers nothing while the company-identity confirmation is waiting for its Yes or No" do
      applicant.update!(company_name: "Acme Widgets Ltd", company_number: "12345678")

      expect(Onboarding::CompanyIdentityConfirmation.pending?(session)).to be(true)
      expect(described_class.for(session)).to be_empty
    end

    it "uses the latest message by time, not by insertion order" do
      say(:applicant, "United Kingdom").update!(created_at: 2.minutes.ago)
      say(:bot, "Which country is the company registered in?").update!(created_at: 1.minute.ago)

      expect(described_class.for(session)).not_to be_empty
    end
  end
end
