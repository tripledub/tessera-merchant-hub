# frozen_string_literal: true

module Kyc
  # Adds a domain by hand (MH-300). A hand-added domain has no evidence by
  # definition and is accepted on creation, so the reviewer must say why it is
  # trusted: otherwise adding by hand would be the way round the rule that an
  # evidence-less domain needs a comment to be accepted.
  #
  # Works on the given (unsaved) domain so a failed attempt can be shown again
  # with what was typed and its errors. Returns true if the domain and its
  # comment were both saved, false otherwise.
  class AddDomainByHand
    def self.call(domain:, name:, justification:, author:)
      new(domain, name, justification, author).call
    end

    def initialize(domain, name, justification, author)
      @domain = domain
      @name = name
      @justification = justification
      @author = author
    end

    def call
      @domain.name = @name
      @domain.justification = @justification

      @domain.valid?
      @domain.errors.add(:justification, :blank) if @justification.to_s.strip.blank?
      return false if @domain.errors.any?

      ApplicantDomain.transaction do
        @domain.save!
        @domain.comments.create!(author: @author, body: @justification.strip)
      end
      true
    end
  end
end
