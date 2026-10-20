# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantSignInCodeMailer, type: :mailer do
  describe "#code" do
    let(:record) { create(:applicant_sign_in_code, email: "invitee@example.com", code: "482913") }
    let(:token) do
      ShortLivedSecret.encrypt("482913", purpose: ApplicantSignInCode::MAIL_PURPOSE, expires_in: ApplicantSignInCode::MAIL_TOKEN_LIFETIME)
    end
    let(:mail) { described_class.code(record, token) }

    it "goes to the address the code was issued for" do
      expect(mail.to).to eq([ "invitee@example.com" ])
    end

    it "keeps the digits out of the subject" do
      expect(mail.subject).to eq("Your Kynetic sign-in code")
      expect(mail.subject).not_to match(/\d{4,}/)
    end

    it "shows the code, when it expires, and what to do if it was not requested, in both parts" do
      bodies = [ mail.html_part.body.to_s, mail.text_part.body.to_s ]

      expect(bodies).to all(include("482913"))
      expect(bodies).to all(include("10 minutes"))
      expect(bodies).to all(match(/didn(?:'|&#39;)t request/i))
    end

    it "is styled through the mailer stylesheet" do
      mail.deliver_now

      html = ActionMailer::Base.deliveries.last.html_part.body.to_s

      expect(html).to include('class="email-code"').or include("email-code")
      expect(html).to include("letter-spacing")
      expect(html).not_to include("<link")
    end

    # MH-414: the six digits wrapped onto two lines on a narrow phone.
    it "keeps the code on one line, with the style inlined into the delivered HTML" do
      mail.deliver_now

      html = Nokogiri::HTML(ActionMailer::Base.deliveries.last.html_part.body.to_s)
      style = html.at_css(".email-code")["style"]

      expect(style).to include("white-space: nowrap")
      expect(style).to match(/font-size: (2[4-9]|3\d)px/)
    end

    it "sends nothing once the encrypted code has expired" do
      mail

      travel_to((ApplicantSignInCode::MAIL_TOKEN_LIFETIME + 1.minute).from_now) do
        expect { described_class.code(record, token).deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
      end
    end

    it "sends nothing for a value that cannot be decrypted" do
      expect { described_class.code(record, "482913").deliver_now }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it "never carries the plaintext code in what is queued" do
      expect { described_class.code(record, token).deliver_later }.to have_enqueued_mail(described_class, :code)

      queued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(queued.to_json).not_to include("482913")
    end
  end
end
