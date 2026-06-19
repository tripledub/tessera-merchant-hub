# frozen_string_literal: true

class AddressMatcherService
  EXACT_THRESHOLD = 0.98
  FUZZY_THRESHOLD = 0.80

  ABBREVIATIONS = {
    /\bst\b/    => "street",
    /\brd\b/    => "road",
    /\bave?\b/  => "avenue",
    /\bln\b/    => "lane",
    /\bdr\b/    => "drive",
    /\bct\b/    => "court",
    /\bpl\b/    => "place",
    /\bsq\b/    => "square",
    /\bcl\b/    => "close",
    /\buk\b/    => "united kingdom"
  }.freeze

  Result = Data.define(:match_method, :match_confidence)

  def self.call(principal:, extracted_address:)
    new(principal: principal, extracted_address: extracted_address).call
  end

  def initialize(principal:, extracted_address:)
    @principal         = principal
    @extracted_address = extracted_address
  end

  def call
    return no_match if @extracted_address.blank?
    return no_match if principal_address.blank?

    score = JaroWinkler.distance(normalise(@extracted_address), normalise(principal_address))

    if score >= EXACT_THRESHOLD
      Result.new(match_method: "exact", match_confidence: 1.0)
    elsif score >= FUZZY_THRESHOLD
      Result.new(match_method: "fuzzy", match_confidence: score.round(3))
    else
      no_match
    end
  end

  private

  def principal_address
    @principal_address ||= [
      @principal.address_line1,
      @principal.address_line2,
      @principal.city,
      @principal.postcode,
      @principal.country
    ].compact_blank.join(", ")
  end

  def normalise(address)
    result = address.downcase.strip.gsub(/\s+/, " ")
    ABBREVIATIONS.each { |pattern, replacement| result = result.gsub(pattern, replacement) }
    result
  end

  def no_match
    Result.new(match_method: nil, match_confidence: nil)
  end
end
