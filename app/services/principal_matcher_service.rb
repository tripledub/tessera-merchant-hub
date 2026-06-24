# frozen_string_literal: true

# Matches an extracted OCR result to an existing KycPrincipal, or creates one.
#
# Passport:
#   Exact name + DOB match → :exact
#   Jaro-Winkler name similarity >= FUZZY_THRESHOLD → :fuzzy with confidence
#   No match → creates new unconfirmed KycPrincipal from extracted data
#
# Utility bill / other documents:
#   Fuzzy name match only (no DOB on these documents)
#   No match → returns nil (document left unlinked)
#
# Returns a Result struct with: principal, match_method, match_confidence
class PrincipalMatcherService
  FUZZY_THRESHOLD = 0.92
  PASSPORT_TYPE   = "passport"

  Result = Data.define(:principal, :match_method, :match_confidence)

  def self.call(applicant:, result:)
    new(applicant: applicant, result: result).call
  end

  def initialize(applicant:, result:)
    @applicant    = applicant
    @result       = result
    @full_name    = result["full_name"].presence
    @date_of_birth = parse_date(result["date_of_birth"])
    @document_type = result["document_type"]
  end

  def call
    return Result.new(principal: nil, match_method: nil, match_confidence: nil) if @full_name.blank?

    exact = find_exact_match
    return Result.new(principal: exact, match_method: "exact", match_confidence: 1.0) if exact

    fuzzy_principal, score = find_fuzzy_match
    return Result.new(principal: fuzzy_principal, match_method: "fuzzy", match_confidence: score.round(3)) if fuzzy_principal

    if passport?
      principal = create_unconfirmed_principal
      Result.new(principal: principal, match_method: "exact", match_confidence: 1.0)
    else
      Result.new(principal: nil, match_method: nil, match_confidence: nil)
    end
  end

  private

  def principals
    @principals ||= @applicant.kyc_principals.to_a
  end

  def find_exact_match
    if passport? && @date_of_birth
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
      score = JaroWinkler.similarity(@full_name.downcase, p.name.downcase)
      if score >= FUZZY_THRESHOLD && score > best_score
        best_score     = score
        best_principal = p
      end
    end

    [ best_principal, best_score ]
  end

  def create_unconfirmed_principal
    @applicant.kyc_principals.create!(
      name:          @full_name,
      date_of_birth: @date_of_birth,
      status:        :unconfirmed,
      role:          :director
    )
  end

  def names_match_exactly?(a, b)
    a.downcase.strip == b.downcase.strip
  end

  def passport?
    @document_type == PASSPORT_TYPE
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue Date::Error, TypeError
    nil
  end
end
