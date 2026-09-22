# frozen_string_literal: true

# MH-314: shared steps for driving a document through classification and
# extraction in a real browser. No ActionCable/AnyCable runs in the test
# environment, so a broadcasted update never reaches the page on its own —
# each step waits for the DOM change its own request produces (proof the
# server-side enqueue already happened), runs the now-queued job inline with
# ActiveJob::TestHelper, then the caller reloads to see the result.
module SystemDocumentPipeline
  def confirm_classification!
    find("[data-action='click->classification#confirm']").click
    expect(page).to have_content(I18n.t("kyc.documents.classification.status.confirmed"))
  end

  # "Run extraction" is button_to with data-turbo-confirm, but this app
  # overrides Turbo.config.forms.confirm (app/javascript/application.js) with
  # an in-page #confirm-modal instead of the native window.confirm dialog, so
  # Capybara's accept_confirm (which waits for a real JS dialog) never fires.
  def run_extraction!(pending_count: 1)
    click_button I18n.t("applicants.show.documents.run_extraction")
    find("#confirm-modal-confirm").click
    expect(page).to have_content(I18n.t("flash.kyc_documents.extraction_started", count: pending_count))
    perform_enqueued_jobs
  end
end

RSpec.configure do |config|
  config.include SystemDocumentPipeline, type: :system
end
