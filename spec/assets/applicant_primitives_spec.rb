# frozen_string_literal: true

require "rails_helper"

# MH-395: shared applicant UI primitives live next to the admin ones in the
# Tailwind source. These specs pin the contract: every kyn-* utility exists,
# uses only kyn-* tokens (no admin scales), has no dark variants, and the
# legacy utilities (36 admin view files use them) are left alone.
RSpec.describe "Applicant UI primitives" do # rubocop:disable RSpec/DescribeClass
  let(:css) { Rails.root.join("app/assets/tailwind/application.css").read }
  let(:kyn_utilities) do
    %w[
      kyn-btn-primary kyn-btn-secondary kyn-input kyn-label kyn-field
      kyn-card kyn-checkbox kyn-check-label kyn-link
    ]
  end
  let(:legacy_utilities) do
    %w[card form-input form-input-error form-label form-error fieldset-error form-select btn btn-primary btn-secondary btn-danger btn-warning badge]
  end

  # Pulls the body of an `@utility name { ... }` block, including nested rules.
  def utility_block(name)
    start = css.index(/^@utility #{Regexp.escape(name)} \{/)
    return nil unless start

    depth = 0
    opened = false
    css[start..].each_char.with_index do |char, index|
      if char == "{"
        depth += 1
        opened = true
      elsif char == "}"
        depth -= 1
      end
      return css[start..(start + index)] if opened && depth.zero?
    end
    nil
  end



  it "defines every applicant primitive" do
    expect(kyn_utilities.reject { |name| utility_block(name) }).to be_empty
  end

  it "styles them from kyn tokens only, with no admin colour scales" do
    admin_scale = /(?<![a-z-])(gray|brand|success|error|warning|orange|blue-light)-\d{2,3}/

    offenders = kyn_utilities.select { |name| utility_block(name).match?(admin_scale) }

    expect(offenders).to be_empty
  end

  it "adds no dark variants to the applicant primitives" do
    offenders = kyn_utilities.select { |name| utility_block(name).include?("dark:") }

    expect(offenders).to be_empty
  end

  it "sizes buttons and inputs for touch (at least 44px)" do
    expect(utility_block("kyn-btn-primary")).to include("min-h-[52px]")
    expect(utility_block("kyn-btn-secondary")).to include("min-h-[52px]")
    expect(utility_block("kyn-input")).to include("min-h-[50px]")
    expect(utility_block("kyn-check-label")).to include("min-h-[44px]")
  end

  it "shows a keyboard focus ring on buttons, inputs, checkboxes and links" do
    %w[kyn-btn-primary kyn-btn-secondary kyn-input kyn-checkbox kyn-link].each do |name|
      expect(utility_block(name)).to include("focus-visible"), "#{name} has no focus-visible style"
    end
  end

  it "drives the input error look from aria-invalid, not from a swapped class" do
    expect(utility_block("kyn-input")).to include('[aria-invalid="true"]')
  end

  it "restyles the inline validation message inside a kyn-field" do
    field = utility_block("kyn-field")

    expect(field).to include("data-form-validation-error")
    expect(field).to include("form-error")
  end

  it "does not edit the legacy shared utilities" do
    expect(legacy_utilities.reject { |name| utility_block(name) }).to be_empty
    expect(utility_block("form-input")).to include("focus:border-brand-500")
    expect(utility_block("form-input-error")).to include("border-error-300")
    expect(utility_block("btn-primary")).to include("bg-brand-500")
    expect(utility_block("card")).to include("rounded-2xl")
  end
end
