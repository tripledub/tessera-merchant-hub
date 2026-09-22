# frozen_string_literal: true

# Toggles the UAT_DB_RESET_ENABLED gate (config/initializers/uat_db_reset.rb)
# for one example group, restoring the original value afterwards — same
# pattern as spec/support/synthetic_data_flag.rb.
RSpec.shared_context "with UAT DB reset enabled" do
  around do |example|
    original = Rails.application.config.x.uat_db_reset_enabled
    Rails.application.config.x.uat_db_reset_enabled = true
    example.run
  ensure
    Rails.application.config.x.uat_db_reset_enabled = original
  end
end

RSpec.shared_context "with UAT DB reset disabled" do
  around do |example|
    original = Rails.application.config.x.uat_db_reset_enabled
    Rails.application.config.x.uat_db_reset_enabled = false
    example.run
  ensure
    Rails.application.config.x.uat_db_reset_enabled = original
  end
end
