# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Runtime gem dependencies" do # rubocop:disable RSpec/DescribeClass
  let(:gemfile) { File.read(File.expand_path("../../Gemfile", __dir__)) }

  it "includes the Anthropic client in the production bundle" do
    anthropic_position = gemfile.index('gem "anthropic"')
    development_group_position = gemfile.index("group :development, :test do")

    expect(anthropic_position).to be < development_group_position
  end
end
