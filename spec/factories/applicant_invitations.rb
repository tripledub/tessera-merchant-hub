# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_invitation do
    applicant
    association :invited_by, factory: [ :user, :psp_admin ]
    email { "applicant@example.com" }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
  end
end
