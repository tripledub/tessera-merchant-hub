# frozen_string_literal: true

# MH-311: lists the synthetic scenario catalogue (config/synthetic/scenarios)
# and lets a tester download a scenario's documents as one zip. Gated the
# same way as MH-309's persona surface.
class Admin::Synthetic::ScenariosController < ApplicationController
  before_action :ensure_synthetic_data_enabled!

  def index
    authorize ::Synthetic::ScenarioCatalogue::Scenario
    @scenarios = ::Synthetic::ScenarioCatalogue.all
  end

  def download
    scenario = ::Synthetic::ScenarioCatalogue.find(params[:id])
    authorize scenario, :download?

    send_data ::Synthetic::ScenarioDocumentPack.call(scenario),
      filename: "#{scenario.id}-documents.zip",
      type: "application/zip",
      disposition: "attachment"
  end

  private

  def ensure_synthetic_data_enabled!
    raise ActiveRecord::RecordNotFound unless Rails.application.config.x.synthetic_data_enabled
  end
end
