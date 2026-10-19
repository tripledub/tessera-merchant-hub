# frozen_string_literal: true

require "rails_helper"

# MH-401: the applicant portal is light only. `dark:` classes are inert there
# (the `dark` variant needs a `.dark` ancestor and the applicant layout never
# adds one), so they are dead code, and nothing should reintroduce a dark-mode
# script or toggle. This scans the applicant-facing views and the applicant-only
# Stimulus controllers. Admin views, the shared `dark:` stylesheet utilities and
# Stimulus controllers also used by admin (tabs, dropzone, charts, ...) are out
# of scope on purpose.
RSpec.describe "Applicant portal is light only" do # rubocop:disable RSpec/DescribeClass
  APPLICANT_FACING_GLOBS = %w[
    app/views/portal/**/*
    app/views/onboarding/**/*
    app/views/applicant_users/**/*
    app/views/applicant_invitation_mailer/**/*
    app/views/layouts/applicant.html.erb
    app/views/layouts/_applicant_*
    app/javascript/controllers/onboarding_chat_controller.js
    app/javascript/controllers/country_picker_controller.js
  ].freeze
  DARK_MODE_PATTERN = /dark:|darkMode|dark-mode|["']dark["']/

  let(:files) do
    APPLICANT_FACING_GLOBS.flat_map { |glob| Dir.glob(Rails.root.join(glob)) }.select { |path| File.file?(path) }.sort
  end

  it "scans a meaningful set of files, so the guard cannot pass by matching nothing" do
    expect(files.size).to be >= 25
    expect(files.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }).to include(
      "app/views/layouts/applicant.html.erb",
      "app/javascript/controllers/onboarding_chat_controller.js",
      "app/javascript/controllers/country_picker_controller.js"
    )
  end

  it "has no dark-mode classes, scripts or toggles in applicant-facing views and controllers" do
    offenders = files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line.strip}" if line.match?(DARK_MODE_PATTERN)
      end
    end

    expect(offenders).to be_empty, "dark-mode references found in applicant-facing code:\n#{offenders.join("\n")}"
  end
end
