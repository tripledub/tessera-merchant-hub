# frozen_string_literal: true

require "rails_helper"

# MH-412: Solid Queue keeps finished jobs, and their arguments, until told not to.
RSpec.describe "Solid Queue recurring schedule", type: :job do
  let(:production) { YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production") }

  it "clears finished jobs every day, keeping a day's worth" do
    task = production.values.find { |entry| entry["command"].to_s.include?("clear_finished_in_batches") }

    expect(task).to be_present
    expect(task["schedule"]).to match(/\Aevery day/)
    expect(task["command"]).to include("finished_before: 1.day.ago")
  end

  it "still runs the document expiry monitoring job" do
    expect(production.values.map { |entry| entry["class"] }).to include("Kyc::DocumentExpiryMonitoringJob")
  end

  it "uses a method that exists on Solid Queue jobs" do
    expect(SolidQueue::Job).to respond_to(:clear_finished_in_batches)
  end
end
