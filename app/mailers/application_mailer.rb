class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  before_action :attach_logo

  private

  def attach_logo
    attachments.inline["kynetic-icon.png"] = Rails.root.join("app/assets/images/kynetic-icon.png").read
  end
end
