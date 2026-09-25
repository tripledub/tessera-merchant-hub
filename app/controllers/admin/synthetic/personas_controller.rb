# frozen_string_literal: true

# MH-309: unlinked, UAT/dev-only admin surface for crafting reusable
# Synthetic::Persona records and generating specimen test documents from
# them. Gated by SYNTHETIC_DATA_ENABLED (config/initializers/synthetic_data.rb,
# introduced for MH-310's fake registry) — with the flag off, every action
# here 404s for every user, including psp_admin, matching the
# applicant-delete gate's own pattern.
class Admin::Synthetic::PersonasController < ApplicationController
  before_action :ensure_synthetic_data_enabled!

  expose(:persona) { params[:id] ? ::Synthetic::Persona.find(params[:id]) : ::Synthetic::Persona.new }

  def index
    authorize ::Synthetic::Persona
    @personas = ::Synthetic::Persona.order(:surname, :given_names)
  end

  def new
    authorize persona
  end

  def create
    authorize persona
    if persona.update(persona_params)
      redirect_to admin_synthetic_persona_path(persona), notice: t("flash.synthetic.personas.create_success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize persona
    @generated_documents = persona.generated_documents.includes(:generated_by).order(created_at: :desc)
    @document_types = Kyc::Synthetic::DocumentGenerators.types
  end

  def export
    authorize persona, :export?
    ::Synthetic::PersonaExport.call(persona)
    redirect_to admin_synthetic_persona_path(persona), notice: t("flash.synthetic.personas.export_success")
  end

  private

  def persona_params
    params.require(:synthetic_persona).permit(:given_names, :surname, :date_of_birth, :sex, :jurisdiction)
  end

  def ensure_synthetic_data_enabled!
    raise ActiveRecord::RecordNotFound unless Rails.application.config.x.synthetic_data_enabled
  end
end
