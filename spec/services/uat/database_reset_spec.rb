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
    end
  end
end
