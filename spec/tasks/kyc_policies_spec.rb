# frozen_string_literal: true

require "rails_helper"
require "rake"

# The task's public name is more useful here than its framework class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "kyc:policies:sync" do
  let(:task) { Rake::Task["kyc:policies:sync"] }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("kyc:policies:sync")
    task.reenable
  end

  it "synchronizes deployed validity policies and prints a summary" do
    expect do
      task.invoke
    end.to output("KYC policies synchronized: 2 created, 0 unchanged\n").to_stdout
      .and change(Kyc::DocumentValidityPolicy, :count).by(2)
  end
end
# rubocop:enable RSpec/DescribeClass
