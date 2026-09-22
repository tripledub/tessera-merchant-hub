# frozen_string_literal: true

# Matches an extracted OCR result to an existing KycPrincipal, or creates one.
#
# document_type is the KycDocument's own document_type (e.g. "passport"), passed in
# by the caller — it is document metadata, not part of the extracted result hash.
#
# Identity documents (Kyc::DocumentCategory.identity? — passport, driving_licence):
#   Exact name + DOB match → :exact
#   Name match against a registry-fetched principal with only a partial
#     (month/year) date of birth (MH-303):
#       Agree  → link, back-fill the principal's full date of birth, :registry_corroborated
#       Disagree → block the auto-link (and don't auto-create a duplicate);
#         Result#dob_mismatch_principal carries the candidate so the document
#         row can show it and a reviewer can resolve it via
#         Kyc::PrincipalMatchOverrideService
#   Jaro-Winkler name similarity >= FUZZY_THRESHOLD → :fuzzy with confidence
#   No match on a passport specifically → creates new unconfirmed KycPrincipal
#     with role :unspecified (MH-307 — a passport alone is no evidence of role)
#   No match on a non-passport identity document → returns nil (left unlinked;
#     auto-creation is deliberately passport-only, see MH-175 design spec)
#
# Proof-of-address / other documents:
#   Fuzzy name match only (no DOB on these documents)
#   No match → returns nil (document left unlinked)
#
# Name comparison normalizes Companies House's "SURNAME, Forenames" format
# (Kyc::CompaniesHouseName) so a registry-fetched principal's name matches
# an extracted "Forenames Surname" the way a human reader would.
#
# Returns a Result struct with: principal, match_method, match_confidence,
# dob_mismatch_principal (nil unless the disagree case above applies)
class PrincipalMatcherService
  FUZZY_THRESHOLD = 0.92
  PASSPORT_TYPE   = "passport"

  Result = Data.define(:principal, :match_method, :match_confidence, :dob_mismatch_principal)

  def self.call(applicant:, document_type:, result:)
    new(applicant: applicant, document_type: document_type, result: result).call
  end

  def initialize(applicant:, document_type:, result:)
    @applicant     = applicant
    @result        = result
    @full_name     = result["full_name"].presence
    @date_of_birth = parse_date(result["date_of_birth"])
    @document_type = document_type
  end

  def call
    return no_match if @full_name.blank?

    exact = find_exact_match
    return Result.new(principal: exact, match_method: "exact", match_confidence: 1.0, dob_mismatch_principal: nil) if exact

    fuzzy_principal, score = find_fuzzy_match
    return match_against(fuzzy_principal, score) if fuzzy_principal

    if auto_creatable_identity?
      principal = create_unconfirmed_principal
      Result.new(principal: principal, match_method: "exact", match_confidence: 1.0, dob_mismatch_principal: nil)
    else
      no_match
    end
  end

  private

  def no_match
    Result.new(principal: nil, match_method: nil, match_confidence: nil, dob_mismatch_principal: nil)
  end

  # MH-303: a fuzzy name match against a registry-fetched principal who only
  # has a partial (month/year) date of birth gets a DOB cross-check before
  # it's treated as an ordinary fuzzy match.
  def match_against(principal, score)
    return fuzzy_result(principal, score) unless registry_partial_dob?(principal)
    return fuzzy_result(principal, score) unless dob_aware_identity? && @date_of_birth

    if @date_of_birth.month == principal.date_of_birth_month && @date_of_birth.year == principal.date_of_birth_year
      principal.update!(date_of_birth: @date_of_birth)
      Result.new(principal: principal, match_method: "registry_corroborated", match_confidence: score.round(3),
                 dob_mismatch_principal: nil)
    else
      Result.new(principal: nil, match_method: nil, match_confidence: nil, dob_mismatch_principal: principal)
    end
  end

  def fuzzy_result(principal, score)
    Result.new(principal: principal, match_method: "fuzzy", match_confidence: score.round(3), dob_mismatch_principal: nil)
  end

  def registry_partial_dob?(principal)
    principal.registry_fetched? && principal.date_of_birth.nil? &&
      principal.date_of_birth_month.present? && principal.date_of_birth_year.present?
  end

  def principals
    @principals ||= @applicant.kyc_principals.to_a
  end

  def find_exact_match
    if dob_aware_identity? && @date_of_birth
      principals.find do |p|
        names_match_exactly?(p.name, @full_name) && p.date_of_birth == @date_of_birth
      end
    else
      principals.find { |p| names_match_exactly?(p.name, @full_name) }
    end
  end

  def find_fuzzy_match
    best_principal = nil
    best_score     = 0.0

    principals.each do |p|
      score = best_name_score(@full_name.downcase, normalized_name(p).downcase)
      if score >= FUZZY_THRESHOLD && score > best_score
        best_score     = score
        best_principal = p
      end
    end

    [ best_principal, best_score ]
  end

  def normalized_name(principal)
    Kyc::CompaniesHouseName.normalize(principal.name)
  end

  def best_name_score(a, b)
    full_score = JaroWinkler.similarity(a, b)
    return full_score if full_score >= FUZZY_THRESHOLD

    first_last_score = JaroWinkler.similarity(first_and_last(a), first_and_last(b))
    [ full_score, first_last_score ].max
  end

  def first_and_last(name)
    parts = name.strip.split
    return name if parts.size <= 2

    "#{parts.first} #{parts.last}"
  end

  # MH-307: a passport alone is no evidence of a directorship — role stays
  # :unspecified until a registry match, a company document, or a reviewer
  # sets the real one.
  def create_unconfirmed_principal
    @applicant.kyc_principals.create!(
      name:          @full_name,
      date_of_birth: @date_of_birth,
      status:        :unconfirmed,
      role:          :unspecified
    )
  end

  def names_match_exactly?(a, b)
    Kyc::CompaniesHouseName.normalize(a).downcase.strip == Kyc::CompaniesHouseName.normalize(b).downcase.strip
  end

  def dob_aware_identity?
    Kyc::DocumentCategory.identity?(@document_type)
  end

  def auto_creatable_identity?
    @document_type == PASSPORT_TYPE
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue Date::Error, TypeError => e
    Rails.logger.warn("PrincipalMatcherService: unparseable date #{value.inspect} — #{e.message}")
    nil
  end
end
