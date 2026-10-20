# frozen_string_literal: true

# MH-389: the source of a record (field == "") or of one field of a record.
# The integer value of each source is its trust rank, so a higher value wins.
class DataProvenance < ApplicationRecord
  belongs_to :applicant

  enum :source, { applicant_declared: 0, document_extracted: 1, registry: 2, staff_verified: 3 }

  validates :record_type, :record_id, presence: true

  def self.rank(source) = sources.fetch(source.to_s)
end
