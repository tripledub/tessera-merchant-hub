# frozen_string_literal: true

# The shape every Registry::Client must return from a successful #fetch, so
# Registry::Lookup, Kyc::PrincipalsFromRegistry and Kyc::OwnershipFromRegistry
# can consume any client without caring which one produced it. Run against
# both Registry::CompaniesHouseUkClient and Registry::SyntheticClient so the
# fake cannot drift from the real contract (MH-310).
#
# The including group must define `result` (a Registry::FetchResult).
RSpec.shared_examples "a registry client success result" do
  let(:director_keys) { %i[name role appointed_on resigned_on date_of_birth_month date_of_birth_year] }
  let(:address_keys) { %i[kind line1 city postcode country] }
  let(:psc_keys) do
    %i[
      name kind natures_of_control notified_on ceased_on nationality
      date_of_birth_month date_of_birth_year line1 city postcode country registration_number
    ]
  end

  it "is a successful FetchResult with no error" do
    expect(result).to be_a(Registry::FetchResult)
    expect(result.success).to be(true)
    expect(result.error_type).to be_nil
  end

  it "carries company details" do
    expect(result.company_name).to be_a(String).and be_present
    expect(result.status).to be_a(String).and be_present
    expect(result.incorporated_on).to be_a(Date)
  end

  it "maps every director to the shared shape" do
    expect(result.directors.map { |d| d.keys.sort }).to all(eq(director_keys.sort))
  end

  it "maps every address to the shared shape" do
    expect(result.addresses.map { |a| a.keys.sort }).to all(eq(address_keys.sort))
  end

  it "maps every person with significant control to the shared shape" do
    expect(result.people_with_significant_control.map { |p| p.keys.sort }).to all(eq(psc_keys.sort))
  end

  it "keeps the raw response keyed like Companies House" do
    expect(result.raw_response.keys).to match_array(%w[company officers persons_with_significant_control])
  end
end
