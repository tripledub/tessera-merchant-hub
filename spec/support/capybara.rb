# frozen_string_literal: true

require "capybara/rspec"
require "capybara/cuprite"

# MH-314: headless Chrome via Cuprite (Ferrum) — drives a real, local Chrome
# install directly, with no chromedriver binary to keep in version-sync with
# it (the usual Selenium pain point). System specs are local-only for now;
# CI has no browser installed.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    process_timeout: 20,
    timeout: 15,
    browser_options: ENV["CI"].present? ? { "no-sandbox" => nil } : {}
  )
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 6

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite
  end

  # Lets a JS-driven upload (dropzone_controller.js) or the extraction-run
  # button actually run its ActiveJob jobs inline, instead of leaving them
  # queued and unexecuted (the default :test adapter behaviour).
  config.include ActiveJob::TestHelper, type: :system
end
