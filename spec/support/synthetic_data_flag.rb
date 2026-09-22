# frozen_string_literal: true

# Toggles the SYNTHETIC_DATA_ENABLED gate (config/initializers/synthetic_data.rb)
# for one example group, restoring the original value afterwards. The gate is
# read from Rails.application.config.x, the same way applicant_delete_enabled
# is stubbed in the applicants request spec.
RSpec.shared_context "with synthetic data enabled" do
  around do |example|
    original = Rails.application.config.x.synthetic_data_enabled
    Rails.application.config.x.synthetic_data_enabled = true
    example.run
  ensure
    Rails.application.config.x.synthetic_data_enabled = original
  end
end

RSpec.shared_context "with synthetic data disabled" do
  around do |example|
    original = Rails.application.config.x.synthetic_data_enabled
    Rails.application.config.x.synthetic_data_enabled = false
    example.run
  ensure
    Rails.application.config.x.synthetic_data_enabled = original
  end
end
