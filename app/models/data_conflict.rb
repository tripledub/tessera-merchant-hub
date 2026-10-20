# frozen_string_literal: true

# MH-389: two sources disagree about a field. Conflicts never block anything;
# they are recorded for staff. Resolving them is a later story.
class DataConflict < ApplicationRecord
  belongs_to :applicant

  enum :held_source, DataProvenance.sources, prefix: :held
  enum :proposed_source, DataProvenance.sources, prefix: :proposed
  enum :status, { open: 0, resolved: 1 }, prefix: true

  validates :record_type, :record_id, :field, :detected_at, presence: true
end
