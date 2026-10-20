# frozen_string_literal: true

FactoryBot.define do
  factory :applicant_sign_in_code do
    transient { code { "123456" } }

    applicant
    email { "applicant@example.com" }
    id { SecureRandom.uuid }
    code_digest { ApplicantSignInCode.digest_for(id: id, code: code) }
    expires_at { ApplicantSignInCode::LIFETIME.from_now }
  end
end
