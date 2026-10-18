# frozen_string_literal: true

require "rails_helper"

# MH-410: an applicant who forgets their password must get a reset email. The
# shared Devise reset template used to call sign_in_count, which only the admin
# User has, so this journey raised. These specs cover it end to end.
RSpec.describe "Applicant password reset", type: :request do
  let(:applicant_user) { create(:applicant_user) }

  def reset_email
    ActionMailer::Base.deliveries.last
  end

  def html_of(mail)
    (mail.html_part || mail).body.decoded
  end

  before { ActionMailer::Base.deliveries.clear }

  it "sends the applicant a reset email instead of raising" do
    post applicant_user_password_path, params: { applicant_user: { email: applicant_user.email } }

    expect(response).to redirect_to(new_applicant_user_session_path)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(reset_email.to).to eq([ applicant_user.email ])
  end

  it "words the email as a reset request, not an invitation" do
    post applicant_user_password_path, params: { applicant_user: { email: applicant_user.email } }

    html = html_of(reset_email)
    expect(html).to include("Someone requested a password reset")
    expect(html).to include(applicant_user.email)
    expect(html).to include("Reset my password")
    expect(html).not_to match(/invited/i)
    expect(html).not_to include("Set my password")
  end

  it "links to the applicant set-new-password page, which accepts a new password and signs the applicant in" do
    post applicant_user_password_path, params: { applicant_user: { email: applicant_user.email } }
    link = Nokogiri::HTML(html_of(reset_email)).at_css("a.email-button")["href"]
    token = Rack::Utils.parse_query(URI(link).query)["reset_password_token"]

    expect(URI(link).path).to eq(edit_applicant_user_password_path)
    expect(token).to be_present

    get edit_applicant_user_password_path(reset_password_token: token)
    expect(response).to have_http_status(:ok)

    put applicant_user_password_path, params: {
      applicant_user: { reset_password_token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    }
    expect(response).to have_http_status(:see_other)

    get portal_root_path
    expect(response).to have_http_status(:ok)
    expect(applicant_user.reload.valid_password?("a-new-password-1")).to be(true)
  end

  it "answers an email with no account exactly like a known one and sends nothing, so accounts cannot be enumerated" do
    post applicant_user_password_path, params: { applicant_user: { email: applicant_user.email } }
    known = [ response.status, response.location ]
    ActionMailer::Base.deliveries.clear

    post applicant_user_password_path, params: { applicant_user: { email: "nobody@example.com" } }

    expect([ response.status, response.location ]).to eq(known)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "leaves the admin reset and invite wording on the shared template" do
    admin = create(:user, :psp_admin)

    invited = Devise::Mailer.reset_password_instructions(admin, "token")
    expect(html_of(invited)).to match(/Someone requested a password reset|invited/i)
  end
end
