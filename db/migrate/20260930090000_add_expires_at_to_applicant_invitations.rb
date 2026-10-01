# frozen_string_literal: true

class AddExpiresAtToApplicantInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :applicant_invitations, :expires_at, :datetime
  end
end
