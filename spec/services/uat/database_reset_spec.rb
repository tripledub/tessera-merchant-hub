# frozen_string_literal: true

require "rails_helper"

# MH-315. Never actually invokes db:drop/db:create/etc against the test
# database — the task_invoker is always injected as a fake recorder, so the
# real destructive Rake tasks are never touched by these specs.
RSpec.describe Uat::DatabaseReset do
  let(:invoked) { [] }
  let(:fake_invoker) { ->(name) { invoked << name } }

  describe ".call" do
    context "when UAT_DB_RESET_ENABLED is not set" do
      include_context "with UAT DB reset disabled"

      it "raises NotEnabled and invokes nothing" do
        expect {
          described_class.call(task_invoker: fake_invoker)
        }.to raise_error(Uat::DatabaseReset::NotEnabled, /UAT_DB_RESET_ENABLED/)

        expect(invoked).to be_empty
      end
    end

    context "when UAT_DB_RESET_ENABLED is set" do
      include_context "with UAT DB reset enabled"

      it "invokes drop, create, schema:load and seed, in that order" do
        described_class.call(task_invoker: fake_invoker)

        expect(invoked).to eq(%w[db:drop db:create db:schema:load db:seed])
      end

      it "does not raise" do
        expect { described_class.call(task_invoker: fake_invoker) }.not_to raise_error
      end

      # Regression: UAT runs RAILS_ENV=production, so db:drop and
      # db:schema:load's own ActiveRecord::Tasks::DatabaseTasks
      # .check_protected_environments! raised ActiveRecord::
      # ProtectedEnvironmentError on the first real UAT deploy of this task,
      # since nothing set DISABLE_DATABASE_ENVIRONMENT_CHECK. Asserting the
      # ENV value each task_invoker call actually sees is the only way this
      # regression shows up without invoking a real Rake::Task — it's
      # invisible to "does it raise" alone, since the fake invoker never
      # reads the ENV var itself.
      it "sets DISABLE_DATABASE_ENVIRONMENT_CHECK for every task invocation" do
        seen = []
        recording_invoker = lambda do |name|
          seen << [ name, ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] ]
        end

        described_class.call(task_invoker: recording_invoker)

        expect(seen).to eq(%w[db:drop db:create db:schema:load db:seed].map { |name| [ name, "1" ] })
      end

      it "restores the prior DISABLE_DATABASE_ENVIRONMENT_CHECK value afterwards" do
        ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = nil

        described_class.call(task_invoker: fake_invoker)

        expect(ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"]).to be_nil
      end

      it "restores a pre-existing DISABLE_DATABASE_ENVIRONMENT_CHECK value afterwards" do
        ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "was-already-set"

        described_class.call(task_invoker: fake_invoker)

        expect(ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"]).to eq("was-already-set")
      ensure
        ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = nil
      end

      it "restores the value even if a task invocation raises" do
        failing_invoker = ->(name) { raise "boom" if name == "db:schema:load" }

        expect { described_class.call(task_invoker: failing_invoker) }.to raise_error("boom")
        expect(ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"]).to be_nil
      end
    end
  end
end
