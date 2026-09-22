# frozen_string_literal: true

namespace :qase do
  desc "Run qase_id-tagged specs and report their results to the Qase MH project (needs QASE_API_TOKEN)"
  task :report, [ :run_title ] => :environment do |_t, args|
    require "open3"

    report_path = Rails.root.join("tmp/qase_results.json")
    title = args[:run_title].presence || "RSpec run #{Time.current.strftime('%Y-%m-%d %H:%M')}"

    puts "Running qase_id-tagged specs..."
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "rspec",
      "--require", Rails.root.join("lib/qase_id_formatter").to_s,
      "--format", "QaseIdFormatter", "--out", report_path.to_s,
      "--format", "progress",
      "--tag", "qase_id"
    )
    puts stdout
    warn stderr if stderr.present?
    puts "rspec exited #{status.exitstatus} — reporting results regardless (pass and fail both go to Qase)."

    run_id = Qase::ResultsReporter.call(report_path: report_path, run_title: title)
    puts "Reported to Qase run #{run_id} (project MH)."
  end
end
