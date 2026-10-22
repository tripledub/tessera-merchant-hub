# frozen_string_literal: true

require "rails_helper"

# MH-422: once a document has been classified (or failed), the chat says so, in
# fixed words saved to the conversation.
RSpec.describe Onboarding::DocumentOutcomeMessage do
  let(:applicant) { create(:applicant) }
  let!(:session) { create(:onboarding_session, applicant: applicant, current_stage: :document_collection) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: "passport", status: :pending) }

  def named(filename)
    allow(document.file).to receive(:filename).and_return(ActiveStorage::Filename.new(filename))
  end

  describe ".record!" do
    it "says a recognised document is recognised and under review, pointing to the checklist" do
      message = described_class.record!(document)

      expect(message).to have_attributes(role: "bot", stage: "document_collection")
      expect(message.content).to eq(
        "I've recognised your Passport and it's under review. Your checklist shows what is still needed."
      )
    end

    it "says when a document could not be recognised, naming the file, and asks for it again" do
      document.update!(document_type: nil)
      named("scan.pdf")

      expect(described_class.record!(document).content).to eq(
        "I couldn't tell what “scan\\.pdf” is. Please check it's one of the documents listed and upload it again."
      )
    end

    it "says when a document could not be read" do
      document.update!(status: :error)
      named("scan.pdf")

      expect(described_class.record!(document).content).to eq(
        "I couldn't read “scan\\.pdf”. Please try uploading it again."
      )
    end

    it "escapes markdown in the file name so it cannot change the message" do
      document.update!(document_type: nil)
      named("**bold** [x](http://evil.example).pdf")

      html = MarkdownRenderer.call(described_class.record!(document).content)

      expect(html).not_to include("<strong>")
      expect(html).not_to include("<a ")
    end

    it "saves which document and outcome it was about, and says it once" do
      first = described_class.record!(document)

      expect(first.structured_data).to include("kyc_document_id" => document.id.to_s, "outcome" => "recognised")
      expect { described_class.record!(document) }.not_to change(OnboardingMessage, :count)
      expect(described_class.record!(document)).to be_nil
    end

    it "says it again when the outcome for the same document changes" do
      described_class.record!(document)
      document.update!(document_type: nil)

      expect { described_class.record!(document) }.to change(OnboardingMessage, :count).by(1)
    end

    it "does nothing for an applicant with no onboarding session" do
      session.destroy!

      expect(described_class.record!(document.reload)).to be_nil
    end

    it "does nothing outside the documents stage" do
      session.update!(current_stage: :directors_ubos)

      expect(described_class.record!(document)).to be_nil
      expect(OnboardingMessage.count).to eq(0)
    end
  end
end
