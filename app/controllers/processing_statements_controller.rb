# frozen_string_literal: true

class ProcessingStatementsController < ApplicationController
  MAPPING_MODAL_ID = "processing-statement-mapping-modal"

  expose(:processing_statement) { ProcessingStatement.find(params[:id]) }

  helper_method :applicant

  def index
    authorize ProcessingStatement, :index?
    @processing_statements = applicant.processing_statements.order(created_at: :desc)
  end

  def new
    authorize ProcessingStatement, :create?
  end

  def create
    authorize ProcessingStatement, :create?

    file = params.dig(:processing_statement, :file)
    if file.blank?
      redirect_to new_applicant_processing_statement_path(applicant), alert: t(".no_file")
      return
    end

    statement = applicant.processing_statements.new

    begin
      statement.file.attach(file)
    rescue ArgumentError, ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => e
      Rails.logger.warn("ProcessingStatementsController: skipping unattachable file — #{e.message}")
      redirect_to new_applicant_processing_statement_path(applicant), alert: t(".no_file")
      return
    end

    unless statement.file.attached? && statement.save
      redirect_to new_applicant_processing_statement_path(applicant),
        alert: statement.errors.full_messages.to_sentence.presence || t(".no_file")
      return
    end

    redirect_to edit_processing_statement_path(statement)
  end

  def edit
    authorize processing_statement, :update?
    @mapping_context = mapping_context

    begin
      @headers = Statements::SpreadsheetReader.new(processing_statement).headers
    rescue StandardError => e
      processing_statement.update!(status: :error, error_message: "Could not read this file: #{e.message}")
      redirect_to processing_statement_path(processing_statement), alert: t(".read_error")
    end
  end

  def update
    authorize processing_statement, :update?

    mapping = params.require(:processing_statement).permit(:date, :amount, :currency, :outcome).to_h.compact_blank
    missing = ProcessingStatement::REQUIRED_FIELDS.map(&:to_s) - mapping.keys

    if missing.any?
      @headers = Statements::SpreadsheetReader.new(processing_statement).headers
      @mapping_context = mapping_context
      @mapping_error = t(".missing_fields", fields: missing.join(", "))

      respond_to do |format|
        format.html do
          render :edit, status: :unprocessable_content
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            MAPPING_MODAL_ID,
            partial: "processing_statements/mapping_modal",
            locals: {
              processing_statement: processing_statement,
              headers: @headers,
              context: @mapping_context,
              mapping_error: @mapping_error
            }
          ), status: :unprocessable_content
        end
      end
      return
    end

    processing_statement.with_lock do
      authorize processing_statement, :update?
      processing_statement.update!(status: :mapped, column_mapping: mapping)
    end
    ImportProcessingStatementJob.perform_later(processing_statement.id, mapping)

    respond_to do |format|
      format.html { redirect_to processing_statement_path(processing_statement), notice: t(".success") }
      format.turbo_stream do
        replacement = if mapping_context == "index"
          turbo_stream.replace(
            processing_statement,
            partial: "processing_statements/statement",
            locals: { statement: processing_statement }
          )
        else
          turbo_stream.replace(
            processing_statement,
            partial: "processing_statements/result",
            locals: { processing_statement: processing_statement }
          )
        end

        render turbo_stream: [ turbo_stream.update(MAPPING_MODAL_ID, ""), replacement ]
      end
    end
  end

  def show
    authorize processing_statement
  end

  def export
    authorize processing_statement, :export?
    send_data Statements::ReportExporter.new(processing_statement).to_csv,
      filename: "processing-statement-#{processing_statement.id}.csv", type: "text/csv"
  end

  def destroy
    authorize processing_statement, :destroy?

    processing_statement.with_lock do
      authorize processing_statement, :destroy?
      processing_statement.kyc_document&.update!(processing_statement: nil, classification_status: :rejected)
      processing_statement.destroy!
    end

    redirect_to applicant_processing_statements_path(applicant)
  end

  private

  def applicant
    @applicant ||= if params[:applicant_id]
      Applicant.find(params[:applicant_id])
    else
      processing_statement.applicant
    end
  end

  def mapping_context
    params[:context] == "index" ? "index" : "show"
  end
end
