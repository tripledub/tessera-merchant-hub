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

  # MH-305: UAT deploys with `rails db:prepare` under systemd and never goes
  # through bin/docker-entrypoint, so policies were only ever published where
  # the entrypoint ran. Hanging the sync off the database tasks covers every
  # deploy path, including local resets.
  describe "database task hooks" do
    %w[db:prepare db:migrate db:setup].each do |name|
      context "when #{name} finishes outside the test environment" do
        # The hook is the last action enhance appended; earlier ones are Rails'.
        let(:hook) { Rake::Task[name].actions.last }

        before do
          allow(Rails.env).to receive(:test?).and_return(false)
          allow(task).to receive(:invoke)
        end

        it "publishes the validity policies" do
          hook.call

          expect(task).to have_received(:invoke)
        end

        it "lets a sync failure fail the task so the deploy stops" do
          allow(task).to receive(:invoke).and_raise(Kyc::PolicyValiditySync::Conflict, "immutable change")

          expect { hook.call }.to raise_error(Kyc::PolicyValiditySync::Conflict, "immutable change")
        end
      end

      it "leaves #{name} alone in the test environment" do
        allow(task).to receive(:invoke)

        Rake::Task[name].actions.last.call

        expect(task).not_to have_received(:invoke)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
