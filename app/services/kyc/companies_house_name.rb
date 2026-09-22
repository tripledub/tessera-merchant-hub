# frozen_string_literal: true

module Kyc
  # MH-303 (AC7): Companies House publishes officer names as
  # "SURNAME, Forenames" (e.g. "SAMPLE, Riley"), while extracted document
  # names read like "Riley Sample". Normalizing to the latter shape before
  # comparing lets PrincipalMatcherService's name matching treat the two as
  # the same person instead of scoring them as dissimilar strings.
  #
  # Only strings that actually look like "X, Y" are rewritten; anything else
  # (including a name that happens to contain a comma for some other reason)
  # is returned unchanged rather than guessed at.
  module CompaniesHouseName
    SURNAME_FORENAMES = /\A([^,]+),\s*(.+)\z/

    def self.normalize(name)
      return name if name.blank?

      match = SURNAME_FORENAMES.match(name.strip)
      return name unless match

      surname, forenames = match.captures
      "#{forenames.strip} #{surname.strip}".squeeze(" ")
    end
  end
end
