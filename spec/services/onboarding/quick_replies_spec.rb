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
  let(:company_info_without_type) { { "company_info" => { "company_name" => "Acme Widgets Ltd" } } }
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

      it "gives each country its flag and Other a globe (MH-402)" do
        expect(described_class.for(session).map(&:icon)).to eq(%w[gb mt cy globe])
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

    context "when the company type is the next thing to ask (MH-391)" do
      before do
        session.update!(stage_data: company_info_without_type)
        say(:bot, "What type of company is it?")
      end

      it "offers the six company types, each sent as an answer" do
        options = described_class.for(session)

        expect(options.map(&:key)).to eq(%i[limited_company plc llp sole_trader partnership other])
        expect(options.map(&:label)).to eq(
          [ "Limited company", "Public limited company (PLC)", "LLP", "Sole trader", "Partnership", "Other" ]
        )
        expect(options.map(&:kind)).to all(eq(:answer))
        expect(options.map(&:field)).to all(eq(:company_type))
      end

      it "gives the company types no icon" do
        expect(described_class.for(session).map(&:icon)).to all(be_nil)
      end

      it "asks for the type before the country" do
        expect(described_class.question(session)).to eq(:company_type)
      end
    end

    it "offers nothing before the company name is known" do
      session.update!(stage_data: {})
      say(:bot, "What is the name of your business?")

      expect(described_class.for(session)).to be_empty
    end

    it "offers the countries when the type is known and the country is next, even if the number and address are not" do
      session.update!(stage_data: { "company_info" => { "company_name" => "Acme", "company_type" => "limited_company" } })
      say(:bot, "Which country is the company registered in?")

      expect(described_class.for(session).map(&:key)).to eq(%i[united_kingdom malta cyprus other])
      expect(described_class.for(session).map(&:field)).to all(eq(:country_of_incorporation))
    end

    it "offers nothing when the next question has no chips" do
      session.update!(stage_data: { "company_info" => { "company_name" => "Acme", "company_type" => "limited_company",
                                                        "country_of_incorporation" => "United Kingdom" } })
      say(:bot, "What is the company's registration number?")

      expect(described_class.for(session)).to be_empty
    end

    it "offers nothing while the registry match waits for its Yes or No" do
      session.update!(stage_data: company_info_without_type.merge("registry_check" => { "state" => "pending" }))
      say(:bot, "I found Acme. Is this your company?")

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
