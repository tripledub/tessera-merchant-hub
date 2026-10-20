# frozen_string_literal: true

# MH-408: remembers that an applicant said "Not now" to the optional "set a
# password" prompt, so it stays gone across sign-ins and devices.
class AddPasswordPromptDismissedAtToApplicantUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :applicant_users, :password_prompt_dismissed_at, :datetime
  end
end
