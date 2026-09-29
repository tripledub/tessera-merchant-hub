# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "spec_helper"

# Configuration is exercised in a separate production-mode Rails process.
RSpec.describe "production mailer configuration" do # rubocop:disable RSpec/DescribeClass
  it "uses the configured application host for HTTPS mail links" do
    rails_root = Pathname(__dir__).join("../..").expand_path
    environment = {
      "APPLICATION_HOST" => "uat.kynetic.id",
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE_DUMMY" => "1"
    }
    command = [
      RbConfig.ruby,
      rails_root.join("bin/rails").to_s,
      "runner",
      "puts Rails.application.config.action_mailer.default_url_options.to_json"
    ]

    output, _error, status = Open3.capture3(environment, *command)

    expect(status).to be_success
    expect(JSON.parse(output.lines.last)).to eq(
      "host" => "uat.kynetic.id",
      "protocol" => "https"
    )
  end
end
