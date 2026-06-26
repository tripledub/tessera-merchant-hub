# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ConversationEngine do
  describe ".respond" do
    let(:adapter_response) do
      {
        "bot_message" => "What type of company is Acme Ltd?",
        "extracted_data" => {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678"
        }
      }
    end

    let(:adapter) { instance_double(Kyc::Inference::Base, generate: adapter_response) }

    it "persists applicant and bot messages around the inference call" do
      session = create(:onboarding_session, current_stage: :company_info)

      result = described_class.respond(
        session: session,
        user_message: "The company is Acme Ltd, registration number 12345678",
        inference_adapter: adapter
      )

      expect(result).to eq(
        bot_message: "What type of company is Acme Ltd?",
        extracted_data: {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678"
        },
        stage_changed: false
      )
      expect(session.onboarding_messages.pluck(:role, :content, :stage)).to eq([
        [ "applicant", "The company is Acme Ltd, registration number 12345678", "company_info" ],
        [ "bot", "What type of company is Acme Ltd?", "company_info" ]
      ])
    end

    it "builds the prompt after saving the applicant message" do
      session = create(:onboarding_session, current_stage: :company_info)

      described_class.respond(session: session, user_message: "Hello", inference_adapter: adapter)

      expect(adapter).to have_received(:generate).with(prompt: include("applicant: Hello"))
    end

    it "captures extracted data and advances when the stage is complete" do
      session = create(:onboarding_session, current_stage: :company_info)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Thanks, let's talk about directors.",
        "extracted_data" => {
          "company_name" => "Acme Ltd",
          "registration_number" => "12345678",
          "company_type" => "limited_company",
          "registered_address" => "1 High Street",
          "country_of_incorporation" => "GB"
        }
      })

      result = described_class.respond(session: session, user_message: "Here are the company details", inference_adapter: adapter)

      session.reload
      expect(session.current_stage).to eq("directors_ubos")
      expect(session.stage_data["company_info"]).to include("company_name" => "Acme Ltd")
      expect(result[:stage_changed]).to be(true)
      expect(result[:bot_message]).to include("Next, let’s add the directors and beneficial owners")
    end

    it "does not auto-advance looping stages after the first complete item" do
      session = create(:onboarding_session, current_stage: :directors_ubos)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Are there any more directors or shareholders?",
        "extracted_data" => {
          "full_name" => "Jane Smith",
          "date_of_birth" => "1980-01-01",
          "nationality" => "GB",
          "role" => "director"
        }
      })

      result = described_class.respond(session: session, user_message: "Jane is a director", inference_adapter: adapter)

      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(result[:stage_changed]).to be(false)
    end

    it "advances a complete looping stage when the inference response says there are no more items" do
      session = create(:onboarding_session, current_stage: :directors_ubos, stage_data: complete_directors_ubos_data)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Thanks, let's move to ownership.",
        "extracted_data" => { "done_adding_items" => true }
      })

      result = described_class.respond(session: session, user_message: "none", inference_adapter: adapter)

      expect(session.reload.current_stage).to eq("ownership")
      expect(session.completed_stages).to include("directors_ubos")
      expect(result[:stage_changed]).to be(true)
      expect(result[:bot_message]).to include("Next, let’s map the ownership structure")
    end

    it "does not advance a looping stage from raw user text without inference confirmation" do
      session = create(:onboarding_session, current_stage: :directors_ubos, stage_data: complete_directors_ubos_data)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Please provide their nationality.",
        "extracted_data" => {}
      })

      result = described_class.respond(session: session, user_message: "I have no middle name", inference_adapter: adapter)

      expect(session.reload.current_stage).to eq("directors_ubos")
      expect(result[:stage_changed]).to be(false)
    end

    it "uses the collected company name in ownership transition prompts" do
      session = create(:onboarding_session, current_stage: :directors_ubos, stage_data: complete_directors_ubos_data.merge(
        "company_info" => { "company_name" => "Acme Payments Ltd" }
      ))
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Thanks, let's move to ownership.",
        "extracted_data" => { "done_adding_items" => true }
      })

      result = described_class.respond(session: session, user_message: "That's everyone", inference_adapter: adapter)

      expect(result[:bot_message]).to include("Who owns or controls Acme Payments Ltd")
      expect(result[:bot_message]).not_to include("Tab Trade Ltd")
    end

    it "does not repeat the document collection transition prompt during document collection" do
      session = create(:onboarding_session, current_stage: :document_collection)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Please upload your proof of address when you have it.",
        "extracted_data" => {}
      })

      result = described_class.respond(session: session, user_message: "ok", inference_adapter: adapter)

      expect(session.reload.current_stage).to eq("document_collection")
      expect(result[:stage_changed]).to be(false)
      expect(result[:bot_message]).to eq("Please upload your proof of address when you have it.")
    end

    it "records a bot response when ownership data uses human-readable owner names" do
      session = create(:onboarding_session, current_stage: :ownership)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Thanks, Patsy Pong has been recorded.",
        "extracted_data" => {
          "owner" => "Patsy Pong",
          "owned_entity" => "McFoo & Sons",
          "percentage" => "31",
          "relationship_type" => "equity"
        }
      })

      expect {
        described_class.respond(session: session, user_message: "31%", inference_adapter: adapter)
      }.not_to change(Kyc::OwnershipEdge, :count)

      expect(session.reload.onboarding_messages.pluck(:role, :content)).to eq([
        [ "applicant", "31%" ],
        [ "bot", "Thanks, Patsy Pong has been recorded." ]
      ])
    end

    it "accepts a JSON string response from the inference adapter" do
      session = create(:onboarding_session, current_stage: :company_info)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        bot_message: "Tell me the company registration number.",
        extracted_data: { company_name: "Acme Ltd" }
      }.to_json)

      result = described_class.respond(session: session, user_message: "Acme Ltd", inference_adapter: adapter)

      expect(result).to include(
        bot_message: "Tell me the company registration number.",
        extracted_data: { "company_name" => "Acme Ltd" },
        stage_changed: false
      )
    end

    it "raises an inference error for malformed adapter responses" do
      session = create(:onboarding_session, current_stage: :company_info)
      adapter = instance_double(Kyc::Inference::Base, generate: { "extracted_data" => {} })

      expect {
        described_class.respond(session: session, user_message: "Hello", inference_adapter: adapter)
      }.to raise_error(Kyc::Inference::Error, /bot_message/)
    end

    it "keeps the applicant message for retry when inference fails" do
      session = create(:onboarding_session, current_stage: :company_info)
      adapter = instance_double(Kyc::Inference::Base)
      allow(adapter).to receive(:generate).and_raise(Kyc::Inference::Error, "timeout")

      expect {
        described_class.respond(session: session, user_message: "Hello", inference_adapter: adapter)
      }.to raise_error(Kyc::Inference::Error, /timeout/)

      expect(session.onboarding_messages.pluck(:role, :content)).to eq([
        [ "applicant", "Hello" ]
      ])
    end

    it "rolls back captured data when bot message persistence fails" do
      session = create(:onboarding_session, current_stage: :company_info)
      allow(OnboardingMessage).to receive(:create!).and_call_original
      allow(OnboardingMessage).to receive(:create!)
        .with(hash_including(role: :bot))
        .and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.respond(session: session, user_message: "Acme Ltd", inference_adapter: adapter)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(session.reload.stage_data).to eq({})
    end
  end

  def complete_directors_ubos_data
    {
      "directors_ubos" => {
        "items" => [
          {
            "full_name" => "Jane Smith",
            "date_of_birth" => "1980-01-01",
            "nationality" => "GB",
            "role" => "director"
          }
        ]
      }
    }
  end
end
