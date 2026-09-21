# frozen_string_literal: true

module Kyc
  # Adds a domain to the blocklist (MH-298). What a psp_admin types or pastes is
  # reduced to the registrable domain the same way extraction reduces what it
  # finds (a URL, a "www." host), so an entry actually matches. Subdomains,
  # emails, IPs and junk are refused, since extraction discards those and an
  # entry for them could never match.
  #
  # Works on the given entry so a failed attempt can be shown again with what was
  # typed and its errors. Returns true if the entry was saved. Adding an entry
  # never changes domains that applicants already have.
  class AddBlocklistEntry
    def self.call(entry:, name:, author:)
      new(entry, name, author).call
    end

    def initialize(entry, name, author)
      @entry = entry
      @name = name
      @author = author
    end

    def call
      @entry.name = @name.to_s.strip

      if @entry.name.blank?
        @entry.errors.add(:name, :blank)
        return false
      end

      registrable = DomainNormalizer.call(@entry.name)
      if registrable.nil?
        @entry.errors.add(:name, I18n.t("admin.domain_blocklist_entries.errors.not_registrable"))
        return false
      end

      @entry.name = registrable
      @entry.created_by = @author
      @entry.save
    end
  end
end
