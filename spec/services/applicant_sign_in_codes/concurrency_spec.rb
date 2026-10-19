# frozen_string_literal: true

require "rails_helper"

# MH-404: the guarantees that only hold under real concurrency (separate
# database connections, committed rows), so these examples are not wrapped in
# the usual rolled-back transaction and clean up after themselves.
RSpec.describe "Sign-in codes under concurrency" do # rubocop:disable RSpec/DescribeClass
  self.use_transactional_tests = false

  let(:email) { "invitee@example.com" }
  let!(:applicant) { create(:applicant) }

  after do
    ApplicantSignInCode.where(applicant_id: applicant.id).delete_all
    ApplicantUser.where(applicant_id: applicant.id).delete_all
    Applicant.where(id: applicant.id).delete_all
  end

  # Runs the blocks at the same moment, each on its own connection.
  def in_parallel(*blocks)
    gate = Concurrent::CountDownLatch.new(1)
    threads = blocks.map do |block|
      Thread.new do
        Thread.current.report_on_exception = false
        ActiveRecord::Base.connection_pool.with_connection do
          gate.wait
          block.call
        end
      end
    end
    gate.count_down
    threads.map(&:value)
  end

  it "accepts the right code exactly once when it is entered twice at the same moment" do
    create(:applicant_sign_in_code, applicant: applicant, email: email, code: "482913")
    verify = -> { ApplicantSignInCodes::Verify.call(applicant: applicant, email: email, code: "482913").status }

    statuses = in_parallel(verify, verify, verify)

    expect(statuses.sort).to eq(%i[used used verified])
  end

  it "cannot be guessed past five attempts by parallel requests" do
    record = create(:applicant_sign_in_code, applicant: applicant, email: email, code: "482913", attempts: 3)
    guess = -> { ApplicantSignInCodes::Verify.call(applicant: applicant, email: email, code: "000000").status }

    statuses = in_parallel(guess, guess, guess, guess)

    expect(statuses.sort).to eq(%i[locked locked locked wrong])
    expect(record.reload.attempts).to eq(5)
  end

  it "issues one code when two requests arrive at the same moment" do
    issue = -> { ApplicantSignInCodes::Issue.call(applicant: applicant, email: email).status }

    statuses = in_parallel(issue, issue, issue)

    expect(statuses.sort).to eq(%i[sent too_soon too_soon])
    expect(ApplicantSignInCode.where(applicant_id: applicant.id).count).to eq(1)
  end
end
