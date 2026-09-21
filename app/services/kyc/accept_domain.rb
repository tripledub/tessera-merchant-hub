# frozen_string_literal: true

module Kyc
  # Accepts a domain (MH-295), recording the reviewer's comment (MH-300).
  #
  # A domain with no evidence document can only be accepted with a comment
  # saying why: extraction is not validation, and a reviewer may legitimately
  # vouch for a domain by eyeballing, but that decision should leave a reason.
  # That includes re-accepting a rejected domain. With evidence, no comment is
  # needed. Evidence deleted later does not undo an acceptance.
  #
  # Returns true, or false with the reason on domain.errors. The comment and the
  # acceptance are saved together or not at all.
  class AcceptDomain
    def self.call(domain:, reviewer:, comment_body: nil)
      new(domain, reviewer, comment_body).call
    end

    def initialize(domain, reviewer, comment_body)
      @domain = domain
      @reviewer = reviewer
      @comment_body = comment_body.to_s.strip
    end

    def call
      if @comment_body.blank? && !@domain.evidence_links.exists?
        @domain.errors.add(:base, I18n.t("kyc.applicant_domains.accept_form.comment_required"))
        return false
      end

      ApplicantDomain.transaction do
        @domain.comments.create!(author: @reviewer, body: @comment_body) if @comment_body.present?
        @domain.update!(review_status: :accepted)
      end
      true
    end
  end
end
