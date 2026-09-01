# frozen_string_literal: true

# Append-only at the app layer — deliberately not a database-enforced
# invariant. `readonly?` blocks direct `.update`/`.destroy` calls on an
# already-persisted comment: a correction is a new comment, not an edit, so
# the thread reflects what was actually said and when. It does NOT block
# `.delete`, `.clear`, `.delete_all`, or association replacement (e.g.
# `kyc_document.comments = []`); those go through raw SQL / bulk deletion
# paths that never consult `readonly?`. True DB-level immutability would
# need a trigger coordinated with the one sanctioned cascade path — judged
# more migration risk/complexity than this feature warrants for now,
# revisit if a real incident or a later phase of MH-274 makes the stronger
# guarantee worth the cost. The only sanctioned deletion path today is the
# cascade delete via `Commentable`'s `dependent: :delete_all` when the
# commentable parent itself is destroyed — nothing else should call those
# other bulk paths directly on Comment.
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"

  validates :body, presence: true

  def readonly?
    persisted?
  end
end
