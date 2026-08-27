# frozen_string_literal: true

FactoryBot.define do
  factory :processing_statement do
    association :applicant
    status { :uploaded }
    column_mapping { {} }
    metrics { {} }

    after(:build) do |statement|
      statement.file.attach(
        io: StringIO.new("Date,Amount,Currency,Status\n2026-04-01,10.00,GBP,approved\n"),
        filename: "statement.csv",
        content_type: "text/csv"
      )
    end
  end
end
