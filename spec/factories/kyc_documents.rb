# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_document do
    association :applicant
    kyc_principal { nil }
    status { :pending }
    result { nil }

    after(:build) do |doc|
      doc.file.attach(
        io: StringIO.new("fake pdf content"),
        filename: "passport.pdf",
        content_type: "application/pdf"
      )
    end

    trait :image do
      after(:build) do |doc|
        doc.file.attach(
          io: StringIO.new("fake jpeg content"),
          filename: "passport.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
