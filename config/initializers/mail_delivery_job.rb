# frozen_string_literal: true

# Background mail jobs take the mailer arguments, which for some mailers include
# one-time links and tokens (applicant invitations, password resets). Keep them
# out of the job log.
ActiveSupport.on_load(:action_mailer) do
  ActionMailer::MailDeliveryJob.log_arguments = false
end
