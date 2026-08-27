# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ProcessingStatements", type: :request do
  include ActiveJob::TestHelper

  let_it_be(:psp_admin) { create(:user, :psp_admin) }
  let_it_be(:applicant) { create(:applicant) }

  let(:csv) do
    <<~CSV
      Txn Date,Value,Currency,Result
      2026-04-01,100.00,GBP,approved
      2026-04-15,50.00,GBP,declined
    CSV
  end

  let(:upload) { Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "statement.csv") }

  before { sign_in psp_admin }

  describe "GET /applicants/:applicant_id/processing_statements" do
    it "lists the applicant's statements with a link back to each one" do
      statement = create(:processing_statement, applicant: applicant, status: :processed)

      get applicant_processing_statements_path(applicant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(processing_statement_path(statement))
    end

    it "shows an empty state when there are none yet" do
      get applicant_processing_statements_path(applicant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("processing_statements.index.empty"))
    end
  end

  describe "GET /applicants/:applicant_id/processing_statements/new" do
    it "renders the upload form" do
      get new_applicant_processing_statement_path(applicant)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /applicants/:applicant_id/processing_statements" do
    it "creates the statement and redirects to the mapping screen" do
      post applicant_processing_statements_path(applicant), params: { processing_statement: { file: upload } }

      statement = ProcessingStatement.last
      expect(response).to redirect_to(edit_processing_statement_path(statement))
      expect(statement.applicant).to eq(applicant)
    end

    it "redirects back to the upload form instead of raising when the file param isn't attachable" do
      # A plain, non-file value in the file param is treated by ActiveStorage
      # as a signed blob ID; a bogus one naturally raises the exact error
      # this rescues, without stubbing ActiveStorage internals.
      expect {
        post applicant_processing_statements_path(applicant), params: { processing_statement: { file: "not-a-signed-id" } }
      }.not_to change(ProcessingStatement, :count)

      expect(response).to redirect_to(new_applicant_processing_statement_path(applicant))
    end
  end

  describe "GET /processing_statements/:id/edit when the file can't be read" do
    it "marks the statement as error and redirects to the overview instead of raising" do
      statement = create(:processing_statement, applicant: applicant)
      reader = instance_double(Statements::SpreadsheetReader)
      allow(reader).to receive(:headers).and_raise(Zip::Error, "corrupt")
      allow(Statements::SpreadsheetReader).to receive(:new).with(statement).and_return(reader)

      get edit_processing_statement_path(statement)

      expect(response).to redirect_to(processing_statement_path(statement))
      statement.reload
      expect(statement.status).to eq("error")
      expect(statement.error_message).to be_present
    end
  end

  describe "PATCH /processing_statements/:id then GET show" do
    let!(:statement) do
      s = create(:processing_statement, applicant: applicant)
      s.file.attach(io: StringIO.new(csv), filename: "statement.csv", content_type: "text/csv")
      s.save!(validate: false)
      s
    end

    it "queues an import job and marks the statement mapped" do
      expect {
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      }.to have_enqueued_job(ImportProcessingStatementJob).with(
        statement.id, { "date" => "Txn Date", "amount" => "Value", "currency" => "Currency", "outcome" => "Result" }
      )

      expect(response).to redirect_to(processing_statement_path(statement))
      statement.reload
      expect(statement.status).to eq("mapped")

      get processing_statement_path(statement)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("processing_statements.show.processing"))
    end

    it "computes metrics and shows the overview once the job runs" do
      perform_enqueued_jobs do
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      end

      statement.reload
      expect(statement.status).to eq("processed")

      get processing_statement_path(statement)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GBP 150.00")
    end

    it "re-renders the mapping form with an error when a required field is missing, without enqueuing a job" do
      expect {
        patch processing_statement_path(statement), params: { processing_statement: { date: "Txn Date" } }
      }.not_to have_enqueued_job(ImportProcessingStatementJob)

      expect(response).to have_http_status(:unprocessable_content)
      statement.reload
      expect(statement.status).to eq("uploaded")
    end

    it "marks the statement as error without raising when the row limit is exceeded" do
      stub_const("ProcessingStatement::MAX_ROWS", 1)

      perform_enqueued_jobs do
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      end

      statement.reload
      expect(statement.status).to eq("error")
      expect(statement.error_message).to match(/exceeds/i)
    end
  end

  describe "GET /processing_statements/:id/export" do
    let!(:statement) do
      create(:processing_statement, applicant: applicant, status: :processed,
        metrics: { "overall" => { "total_volume" => { "GBP" => "150.0" } }, "by_month" => {} })
    end

    it "returns a CSV file" do
      get export_processing_statement_path(statement)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("GBP 150.00")
    end
  end

  describe "GET /processing_statements/:id/export when the statement isn't processed yet" do
    it "is forbidden" do
      statement = create(:processing_statement, applicant: applicant, status: :mapped)

      get export_processing_statement_path(statement)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
