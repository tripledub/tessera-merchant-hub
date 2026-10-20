# frozen_string_literal: true

require "rails_helper"

# MH-408: the "your password was changed" email for applicants, in the same look
# as the reset email (MH-410). Devise's own mailer sends it.
RSpec.describe "Applicant password-changed email", type: :mailer do
  let(:user) { create(:applicant_user, email: "applicant@example.com") }
  let(:mail) { Devise::Mailer.password_change(user, {}) }

  it "goes to the applicant with the applicant subject" do
    expect(mail.to).to eq([ "applicant@example.com" ])
    expect(mail.subject).to eq("Your Kynetic password was changed")
  end

  it "says the password was set or changed and what to do if it wasn't them, in both parts" do
    bodies = [ mail.html_part.body.to_s, mail.text_part.body.to_s ]

    expect(bodies).to all(match(/password was (set|changed)/i))
    expect(bodies).to all(match(/wasn(?:'|&#39;)t you/i))
    expect(bodies).to all(include("applicant@example.com"))
  end

  it "carries no link, token or password" do
    expect(mail.html_part.body.to_s).not_to match(/reset_password_token|password123/)
    expect(mail.text_part.body.to_s).not_to include("reset_password_token")
  end

  it "is styled through the mailer stylesheet" do
    mail.deliver_now

    html = ActionMailer::Base.deliveries.last.html_part.body.to_s

    expect(html).to include('style="')
    expect(html).not_to include("<link")
  end

  it "leaves the admin user's wording on the shared Devise template" do
    admin = create(:user, :psp_admin)

    mail = Devise::Mailer.password_change(admin, {})

    expect(mail.subject).to eq("Password Changed")
  end
end
