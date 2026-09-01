# frozen_string_literal: true

# Append-only, within limits. `readonly?` blocks direct `.update`/`.destroy`
# calls on an already-persisted comment — a correction is a new comment, not
# an edit, so the thread reflects what was actually said and when. It does
# NOT block `.delete`, `.clear`, `.delete_all`, or association replacement
# (e.g. `kyc_document.comments = []`); those go through raw SQL / bulk
# deletion paths that never consult `readonly?`. Full DB-level immutability
# would need a database trigger, which is out of scope here. The only
# sanctioned deletion path in this codebase is the cascade delete via
# `Commentable`'s `dependent: :delete_all` when the commentable parent
# itself is destroyed — nothing else should call those other paths directly
# on Comment.
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"

  validates :body, presence: true

  def readonly?
    persisted?
  end
end
