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

    it "lists the actual checklist items in the document collection transition prompt" do
      session = create(:onboarding_session, current_stage: :jurisdictions, stage_data: complete_directors_ubos_data.merge(
        "jurisdictions" => { "items" => [ { "country" => "GB" } ] }
      ))
      create(:kyc_principal, applicant: session.applicant, name: "Jane Smith", source: :applicant_declared)
      adapter = instance_double(Kyc::Inference::Base, generate: {
        "bot_message" => "Thanks, that's all the jurisdictions noted.",
        "extracted_data" => { "done_adding_items" => true }
      })

      result = described_class.respond(session: session, user_message: "Done", inference_adapter: adapter)

      expect(result[:bot_message]).to include("Proof of identity for Jane Smith")
      expect(result[:bot_message]).not_to match(/^- $/)
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

    it "intercepts a recognized control command before calling inference" do
      session = create(:onboarding_session, current_stage: :company_info)
      adapter = instance_double(Kyc::Inference::Base)
      allow(adapter).to receive(:generate)

      result = described_class.respond(session: session, user_message: "help", inference_adapter: adapter)

      expect(adapter).not_to have_received(:generate)
      expect(result[:bot_message]).to include("help")
      expect(result[:stage_changed]).to be(false)
      expect(session.onboarding_messages.pluck(:role, :content)).to eq([
        [ "applicant", "help" ],
        [ "bot", result[:bot_message] ]
      ])
    end

    it "does not intercept ordinary conversational messages" do
      session = create(:onboarding_session, current_stage: :company_info)

      described_class.respond(session: session, user_message: "The company is Acme Ltd", inference_adapter: adapter)

      expect(adapter).to have_received(:generate)
    end
  end

  describe ".respond with stream: true" do
    let(:separator) { Onboarding::PromptBuilder::STREAM_SEPARATOR }
    let(:streaming_adapter) do
      instance_double(Kyc::Inference::Base).tap do |adapter|
        allow(adapter).to receive(:generate).with(prompt: anything, stream: true) do |&block|
          chunks = [
            "Thanks for that.",
            "\n#{separator}\n",
            '{"extracted_data":{"company_name":"Acme Ltd"}}'
          ]
          chunks.each { |c| block.call(Struct.new(:content).new(c)) }
        end
      end
    end

    it "broadcasts tokens before the separator and broadcasts a complete event" do
      session = create(:onboarding_session, current_stage: :company_info)
      broadcasts = []
      allow(ActionCable.server).to receive(:broadcast) { |channel, data| broadcasts << [ channel, data ] }

      described_class.respond(
        session: session,
        user_message: "Acme Ltd",
        stream: true,
        inference_adapter: streaming_adapter
      )

      token_broadcasts = broadcasts.select { |_, d| d[:type] == "token" }
      expect(token_broadcasts.map { |_, d| d[:content] }.join).to eq("Thanks for that.")

      complete_broadcast = broadcasts.find { |_, d| d[:type] == "complete" }
      expect(complete_broadcast).not_to be_nil
      expect(complete_broadcast[1][:bot_message]).to include("Thanks for that.")
      expect(complete_broadcast[1][:stage_changed]).to be(false)
    end

    it "persists the applicant and bot messages" do
      session = create(:onboarding_session, current_stage: :company_info)
      allow(ActionCable.server).to receive(:broadcast)

      described_class.respond(
        session: session,
        user_message: "Acme Ltd",
        stream: true,
        inference_adapter: streaming_adapter
      )

      messages = session.onboarding_messages.order(:created_at)
      expect(messages.pluck(:role)).to eq([ "applicant", "bot" ])
      expect(messages.last.content).to eq("Thanks for that.")
    end

    it "does not broadcast tokens that come after the separator" do
      session = create(:onboarding_session, current_stage: :company_info)
      token_contents = []
      allow(ActionCable.server).to receive(:broadcast) do |_ch, data|
        token_contents << data[:content] if data[:type] == "token"
      end

      described_class.respond(
        session: session,
        user_message: "Acme Ltd",
        stream: true,
        inference_adapter: streaming_adapter
      )

      expect(token_contents.join).not_to include(separator)
      expect(token_contents.join).not_to include("extracted_data")
    end

    it "broadcasts an error event and re-raises on failure" do
      session = create(:onboarding_session, current_stage: :company_info)
      broken_adapter = instance_double(Kyc::Inference::Base)
      allow(broken_adapter).to receive(:generate).and_raise(Kyc::Inference::Error, "API failure")
      allow(ActionCable.server).to receive(:broadcast)

      expect {
        described_class.respond(
          session: session,
          user_message: "Hello",
          stream: true,
          inference_adapter: broken_adapter
        )
      }.to raise_error(Kyc::Inference::Error)

      expect(ActionCable.server).to have_received(:broadcast).with(
        "onboarding:#{session.id}",
        hash_including(type: "error")
      )
    end

    it "broadcasts a complete event for an intercepted command without streaming tokens" do
      session = create(:onboarding_session, current_stage: :company_info)
      broadcasts = []
      allow(ActionCable.server).to receive(:broadcast) { |channel, data| broadcasts << [ channel, data ] }

      result = described_class.respond(
        session: session,
        user_message: "save",
        stream: true,
        inference_adapter: streaming_adapter
      )

      expect(streaming_adapter).not_to have_received(:generate)
      expect(broadcasts.map { |_, d| d[:type] }).to eq([ "complete" ])
      expect(broadcasts.first[1][:bot_message]).to match(/saved/i)
      expect(result[:bot_message]).to match(/saved/i)
    end

    it "broadcasts an error event and re-raises when handling an intercepted command fails" do
      session = create(:onboarding_session, current_stage: :company_info)
      allow(ActionCable.server).to receive(:broadcast)
      allow(OnboardingMessage).to receive(:create!).and_call_original
      allow(OnboardingMessage).to receive(:create!)
        .with(hash_including(role: :bot))
        .and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.respond(
          session: session,
          user_message: "help",
          stream: true,
          inference_adapter: streaming_adapter
        )
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(streaming_adapter).not_to have_received(:generate)
      expect(ActionCable.server).to have_received(:broadcast).with(
        "onboarding:#{session.id}",
        hash_including(type: "error")
      )
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
