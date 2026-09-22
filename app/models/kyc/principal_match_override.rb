# frozen_string_literal: true

module Kyc
  # MH-303: audit row for a reviewer resolving a registry date-of-birth
  # mismatch (see PrincipalMatcherService and Kyc::PrincipalMatchOverrideService).
  # Append-only — a document can accumulate several if it's revisited.
  class PrincipalMatchOverride < ApplicationRecord
    self.table_name = "kyc_principal_match_overrides"

    belongs_to :kyc_document
    belongs_to :kyc_principal
    belongs_to :resolved_by, class_name: "User"

    enum :resolution, { link_anyway: 0, different_person: 1 }

    validates :reason, presence: true
  end
end
