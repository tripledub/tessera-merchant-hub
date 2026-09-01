# frozen_string_literal: true

# Append-only. No update/destroy — a correction is a new comment, not an
# edit, so the thread always reflects what was actually said and when.
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"

  validates :body, presence: true

  default_scope { order(created_at: :asc) }
end
