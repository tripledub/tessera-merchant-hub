# frozen_string_literal: true

# MH-309: generates a synthetic document PDF for a persona and streams it for
# download, logging the acting user and the options used (both as a log line
# and as a Synthetic::GeneratedDocument row, which is what the persona page's
# "documents generated" history reads from).
class Admin::Synthetic::PersonaDocumentsController < ApplicationController
  expose(:persona) { ::Synthetic::Persona.find(params[:persona_id]) }

  before_action :ensure_synthetic_data_enabled!

  def create
    authorize persona, :generate_document?

    document_type = params[:document_type].to_s
    generator = Kyc::Synthetic::DocumentGenerators.for(document_type)
    options = document_options
    pdf_data = generator.call(persona: persona, options: options)

    persona.generated_documents.create!(document_type: document_type, options: options, generated_by: current_user)
    Rails.logger.info(
      "Synthetic::PersonaDocuments: #{current_user.email} generated a #{document_type} " \
        "for persona #{persona.id} with options #{options.inspect}"
    )

    send_data pdf_data,
      filename: "#{persona.slug}-#{document_type}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ArgumentError, KeyError
    head :unprocessable_content
  end

  private

  def document_options
    params.fetch(:options, ActionController::Parameters.new)
      .permit(:place_of_birth, :passport_number, :expiry_preset).to_h.symbolize_keys
  end

  def ensure_synthetic_data_enabled!
    raise ActiveRecord::RecordNotFound unless Rails.application.config.x.synthetic_data_enabled
  end
end
