# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ProcessingStatements", type: :request do
  include ActiveJob::TestHelper

  MAPPING_MODAL_ID = "processing-statement-mapping-modal"

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
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("turbo-cable-stream-source[signed-stream-name]")).to be_present
      expect(page.at_css("#processing_statement_#{statement.id}")).to be_present
    end

    it "shows an empty state when there are none yet" do
      get applicant_processing_statements_path(applicant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("processing_statements.index.empty"))
    end

    it "offers uploaded statements for mapping in the shared modal" do
      statement = create(:processing_statement, applicant: applicant, status: :uploaded)

      get applicant_processing_statements_path(applicant)

      page = Nokogiri::HTML(response.body)
      map_link = page.at_css("a[href='#{edit_processing_statement_path(statement, context: "index")}']")
      expect(map_link&.text&.strip).to eq(I18n.t("processing_statements.actions.map"))
      expect(map_link&.attr("data-turbo-frame")).to eq(MAPPING_MODAL_ID)
      expect(page.at_css("turbo-frame##{MAPPING_MODAL_ID}")).to be_present
    end

    it "offers errored statements for remapping and removal" do
      statement = create(:processing_statement, applicant: applicant, status: :error)

      get applicant_processing_statements_path(applicant)

      page = Nokogiri::HTML(response.body)
      row = page.at_css("#processing_statement_#{statement.id}")
      expect(row.at_css("a[data-processing-statement-recovery-target='remap']").text.strip)
        .to eq(I18n.t("processing_statements.actions.remap"))
      remove_form = row.at_css("form[action='#{processing_statement_path(statement)}']")
      expect(remove_form).to be_present
      expect(remove_form.at_css("button")&.text&.strip).to eq(I18n.t("processing_statements.actions.remove"))
      expect(remove_form.at_css("button")&.attr("data-turbo-confirm"))
        .to eq(I18n.t("processing_statements.actions.remove_confirm"))
      expect(row.at_css("#processing_statement_status_#{statement.id} [data-processing-statement-recovery-target='remap']"))
        .to be_nil
    end

    it "does not offer recovery actions to PSP support users" do
      uploaded = create(:processing_statement, applicant: applicant, status: :uploaded)
      errored = create(:processing_statement, applicant: applicant, status: :error)
      sign_in create(:user, :psp_support)

      get applicant_processing_statements_path(applicant)

      page = Nokogiri::HTML(response.body)
      [ uploaded, errored ].each do |statement|
        row = page.at_css("#processing_statement_#{statement.id}")
        expect(row.at_css("[data-processing-statement-recovery-target='map']")).to be_nil
        expect(row.at_css("[data-processing-statement-recovery-target='remap']")).to be_nil
        expect(row.at_css("[data-processing-statement-recovery-target='remove']")).to be_nil
      end
    end

    it "does not offer mapping or removal actions for locked statements" do
      mapped = create(:processing_statement, applicant: applicant, status: :mapped)
      processed = create(:processing_statement, applicant: applicant, status: :processed)

      get applicant_processing_statements_path(applicant)

      page = Nokogiri::HTML(response.body)
      [ mapped, processed ].each do |statement|
        row = page.at_css("#processing_statement_#{statement.id}")
        expect(row.at_css("[data-processing-statement-recovery-target='map']").attribute("hidden")).to be_present
        expect(row.at_css("[data-processing-statement-recovery-target='remap']").attribute("hidden")).to be_present
        expect(row.at_css("[data-processing-statement-recovery-target='remove']").attribute("hidden")).to be_present
      end
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
    it "renders the reusable form as a full page for a direct HTML request" do
      statement = create(:processing_statement, applicant: applicant)

      get edit_processing_statement_path(statement)

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.at_css("h1")&.text).to include(I18n.t("processing_statements.edit.title"))
      expect(page.at_css("form[action='#{processing_statement_path(statement)}']")).to be_present
    end

    it "renders the reusable form in an accessible modal for a Turbo Frame request" do
      statement = create(:processing_statement, applicant: applicant)

      get edit_processing_statement_path(statement, context: "index"), headers: { "Turbo-Frame" => MAPPING_MODAL_ID }

      page = Nokogiri::HTML(response.body)
      modal = page.at_css("turbo-frame##{MAPPING_MODAL_ID} [role='dialog']")
      expect(response).to have_http_status(:ok)
      expect(modal&.attr("aria-modal")).to eq("true")
      expect(modal&.attr("aria-labelledby")).to be_present
      expect(modal&.attr("data-action")).to include("keydown.tab->modal#trapFocus")
      expect(modal&.to_html).not_to include("modal#nothing")
      expect(modal.at_css("button[aria-label='#{I18n.t("processing_statements.mapping_modal.close")}']")).to be_present
      expect(modal.at_css("form[action='#{processing_statement_path(statement)}']")).to be_present
    end

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

    it "does not persist file-reader exception details" do
      statement = create(:processing_statement, applicant: applicant)
      sensitive_detail = "customer@example.test"
      reader = instance_double(Statements::SpreadsheetReader)
      allow(reader).to receive(:headers).and_raise(Zip::Error, sensitive_detail)
      allow(Statements::SpreadsheetReader).to receive(:new).with(statement).and_return(reader)

      get edit_processing_statement_path(statement)

      expect(statement.reload.error_message).to eq(I18n.t("processing_statements.edit.read_error"))
      expect(statement.error_message).not_to include(sensitive_detail)
    end

    it "rejects a locked statement without changing its state" do
      statement = create(:processing_statement, applicant: applicant, status: :mapped)

      get edit_processing_statement_path(statement)

      expect(response).to have_http_status(:forbidden)
      expect(statement.reload.status).to eq("mapped")
    end

    it "rejects a non-admin PSP user without changing the statement" do
      statement = create(:processing_statement, applicant: applicant, status: :uploaded)
      sign_in create(:user, :psp_support)

      get edit_processing_statement_path(statement)

      expect(response).to have_http_status(:forbidden)
      expect(statement.reload.status).to eq("uploaded")
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

    it "closes the modal and broadcasts the mapped index row after a valid Turbo submission" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      expect {
        patch processing_statement_path(statement), params: {
          context: "index",
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }, headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => MAPPING_MODAL_ID }
      }.to have_enqueued_job(ImportProcessingStatementJob)

      streams = Nokogiri::HTML.fragment(response.body)
      modal_stream = streams.at_css("turbo-stream[action='update'][target='#{MAPPING_MODAL_ID}']")
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(modal_stream).to be_present
      expect(modal_stream.at_css("template").text.strip).to be_empty
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_row_#{statement.id}",
        hash_including(
          partial: "processing_statements/statement_status",
          locals: { statement: statement }
        )
      )
    end

    it "does not overwrite an import that completes before the Turbo response renders" do
      allow(ImportProcessingStatementJob).to receive(:perform_later) do |statement_id, mapping|
        ImportProcessingStatementJob.perform_now(statement_id, mapping)
      end

      patch processing_statement_path(statement), params: {
        context: "index",
        processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
      }, headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => MAPPING_MODAL_ID }

      streams = Nokogiri::HTML.fragment(response.body)
      row_stream = streams.at_css("turbo-stream[action='replace'][target='processing_statement_#{statement.id}']")
      expect(statement.reload.status).to eq("processed")
      expect(row_stream).to be_nil
    end

    it "closes the modal and broadcasts the mapped detail result after a valid Turbo submission" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      patch processing_statement_path(statement), params: {
        context: "show",
        processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
      }, headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => MAPPING_MODAL_ID }

      streams = Nokogiri::HTML.fragment(response.body)
      expect(response).to have_http_status(:ok)
      expect(streams.at_css("turbo-stream[action='update'][target='#{MAPPING_MODAL_ID}']")).to be_present
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_#{statement.id}",
        hash_including(
          partial: "processing_statements/result_content",
          locals: { processing_statement: statement }
        )
      )
    end

    it "keeps the modal open with the mapping error after an invalid Turbo submission" do
      expect {
        patch processing_statement_path(statement), params: {
          context: "index", processing_statement: { date: "Txn Date" }
        }, headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => MAPPING_MODAL_ID }
      }.not_to have_enqueued_job(ImportProcessingStatementJob)

      streams = Nokogiri::HTML.fragment(response.body)
      modal_stream = streams.at_css("turbo-stream[action='update'][target='#{MAPPING_MODAL_ID}']")
      expect(response).to have_http_status(:unprocessable_content)
      expect(modal_stream).to be_present
      expect(modal_stream.at_css("[role='dialog']")).to be_present
      expect(modal_stream.at_css("[role='alert']")&.text).to include("amount, currency, outcome")
      expect(modal_stream.at_css("form[action='#{processing_statement_path(statement)}']")).to be_present
      expect(statement.reload.status).to eq("uploaded")
    end

    it "preserves valid submitted selections after an invalid Turbo submission" do
      patch processing_statement_path(statement), params: {
        context: "index",
        processing_statement: { date: "Txn Date", amount: "Value", currency: "", outcome: "Result" }
      }, headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => MAPPING_MODAL_ID }

      modal = Nokogiri::HTML.fragment(response.body)
      expect(modal.at_css("select[name='processing_statement[date]'] option[selected]")&.attr("value")).to eq("Txn Date")
      expect(modal.at_css("select[name='processing_statement[amount]'] option[selected]")&.attr("value")).to eq("Value")
      expect(modal.at_css("select[name='processing_statement[outcome]'] option[selected]")&.attr("value")).to eq("Result")
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

    it "allows an errored statement to be remapped" do
      statement.update!(status: :error, error_message: "Invalid date")

      expect {
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      }.to have_enqueued_job(ImportProcessingStatementJob)

      expect(response).to redirect_to(processing_statement_path(statement))
      expect(statement.reload.status).to eq("mapped")
    end

    it "rejects a mapping attempt after the statement is locked" do
      statement.update!(status: :mapped)

      expect {
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      }.not_to have_enqueued_job(ImportProcessingStatementJob)

      expect(response).to have_http_status(:forbidden)
      expect(statement.reload.status).to eq("mapped")
    end

    it "rejects a mapping attempt by a non-admin PSP user" do
      sign_in create(:user, :psp_support)

      expect {
        patch processing_statement_path(statement), params: {
          processing_statement: { date: "Txn Date", amount: "Value", currency: "Currency", outcome: "Result" }
        }
      }.not_to have_enqueued_job(ImportProcessingStatementJob)

      expect(response).to have_http_status(:forbidden)
      expect(statement.reload.status).to eq("uploaded")
    end

    it "rejects a malformed mapping request for a locked statement before reading its parameters" do
      statement.update!(status: :processed)

      patch processing_statement_path(statement)

      expect(response).to have_http_status(:forbidden)
      expect(statement.reload.status).to eq("processed")
    end
  end

  describe "DELETE /processing_statements/:id" do
    it "removes an errored statement while retaining and rejecting its linked KYC document" do
      statement = create(:processing_statement, applicant: applicant, status: :error)
      other_statement = create(:processing_statement, applicant: applicant, status: :error)
      document = create(:kyc_document, applicant: applicant, processing_statement: statement,
        classification_status: :confirmed)

      expect {
        delete processing_statement_path(statement)
      }.to change(ProcessingStatement, :count).by(-1)

      expect(response).to redirect_to(applicant_processing_statements_path(applicant))
      expect(KycDocument.find_by(id: document.id)).to be_present
      expect(document.reload).to have_attributes(processing_statement_id: nil, classification_status: "rejected")
      expect(ProcessingStatement.find_by(id: other_statement.id)).to be_present
    end

    it "rejects removal of a statement that has not errored" do
      statement = create(:processing_statement, applicant: applicant, status: :processed)

      expect {
        delete processing_statement_path(statement)
      }.not_to change(ProcessingStatement, :count)

      expect(response).to have_http_status(:forbidden)
      expect(ProcessingStatement.find_by(id: statement.id)).to be_present
    end

    it "rejects removal by a non-admin PSP user" do
      statement = create(:processing_statement, applicant: applicant, status: :error)
      sign_in create(:user, :psp_support)

      expect {
        delete processing_statement_path(statement)
      }.not_to change(ProcessingStatement, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /processing_statements/:id" do
    it "subscribes to live updates using a stable detail target" do
      statement = create(:processing_statement, applicant: applicant, status: :mapped)

      get processing_statement_path(statement)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("turbo-cable-stream-source[signed-stream-name]")).to be_present
      expect(page.at_css("#processing_statement_#{statement.id}")).to be_present
    end

    it "offers an uploaded statement for mapping in the shared modal" do
      statement = create(:processing_statement, applicant: applicant, status: :uploaded)

      get processing_statement_path(statement)

      page = Nokogiri::HTML(response.body)
      result = page.at_css("#processing_statement_#{statement.id}")
      map_link = result.at_css("a[href='#{edit_processing_statement_path(statement, context: "show")}']")
      expect(map_link&.text&.strip).to eq(I18n.t("processing_statements.actions.map"))
      expect(map_link&.attr("data-turbo-frame")).to eq(MAPPING_MODAL_ID)
      expect(page.at_css("turbo-frame##{MAPPING_MODAL_ID}")).to be_present
    end

    it "offers an errored statement for remapping and removal" do
      statement = create(:processing_statement, applicant: applicant, status: :error,
        error_message: "Row 4, amount (Value): invalid decimal value 'bad'")

      get processing_statement_path(statement)

      result = Nokogiri::HTML(response.body).at_css("#processing_statement_#{statement.id}")
      expect(result.at_css("a[data-processing-statement-recovery-target='remap']")&.text&.strip)
        .to eq(I18n.t("processing_statements.actions.remap"))
      expect(result.at_css("form[action='#{processing_statement_path(statement)}']")).to be_present
      expect(result.at_css("#processing_statement_result_#{statement.id} [data-processing-statement-recovery-target='remap']"))
        .to be_nil
    end

    it "does not offer recovery actions to a PSP support user" do
      statement = create(:processing_statement, applicant: applicant, status: :error)
      sign_in create(:user, :psp_support)

      get processing_statement_path(statement)

      result = Nokogiri::HTML(response.body).at_css("#processing_statement_#{statement.id}")
      expect(result.at_css("a[href^='#{edit_processing_statement_path(statement)}']")).to be_nil
      expect(result.at_css("form[action='#{processing_statement_path(statement)}']")).to be_nil
    end

    it "does not offer mapping or removal actions for locked statements" do
      %i[mapped processed].each do |status|
        statement = create(:processing_statement, applicant: applicant, status: status)

        get processing_statement_path(statement)

        result = Nokogiri::HTML(response.body).at_css("#processing_statement_#{statement.id}")
        expect(result.at_css("[data-processing-statement-recovery-target='map']").attribute("hidden")).to be_present
        expect(result.at_css("[data-processing-statement-recovery-target='remap']").attribute("hidden")).to be_present
        expect(result.at_css("[data-processing-statement-recovery-target='remove']").attribute("hidden")).to be_present
      end
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
