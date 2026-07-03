# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Runtime gem dependencies" do # rubocop:disable RSpec/DescribeClass
  let(:gemfile) { File.read(File.expand_path("../../Gemfile", __dir__)) }

  it "includes the RubyLLM client in the production bundle" do
    ruby_llm_position = gemfile.index('gem "ruby_llm"')
    development_group_position = gemfile.index("group :development, :test do")

    expect(ruby_llm_position).to be < development_group_position
  end
end
