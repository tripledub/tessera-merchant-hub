# frozen_string_literal: true

require "rails_helper"
require "rake"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "db:reset_and_seed" do
  let(:task) { Rake::Task["db:reset_and_seed"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:reset_and_seed")
    task.reenable
  end

  it "delegates to Uat::DatabaseReset and prints a confirmation" do
    allow(Uat::DatabaseReset).to receive(:call)

    expect { task.invoke }.to output(/Database reset and seeded\./).to_stdout
    expect(Uat::DatabaseReset).to have_received(:call)
  end

  it "aborts with the service's message instead of raising when the gate is off" do
    allow(Uat::DatabaseReset).to receive(:call).and_raise(Uat::DatabaseReset::NotEnabled, "UAT_DB_RESET_ENABLED is not set")

    expect { task.invoke }.to raise_error(SystemExit)
      .and output(/UAT_DB_RESET_ENABLED is not set/).to_stderr
  end
end
# rubocop:enable RSpec/DescribeClass
