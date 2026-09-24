# frozen_string_literal: true

module Synthetic
  # MH-309: the reusable, persisted unit of "a fake person" that synthetic
  # document generators (starting with Kyc::Synthetic::PassportPdf) render
  # from. Only reachable through the gated /admin/synthetic surface.
  class Persona < ApplicationRecord
    self.table_name = "synthetic_personas"

    has_many :generated_documents, class_name: "Synthetic::GeneratedDocument",
      foreign_key: "synthetic_persona_id", inverse_of: :synthetic_persona, dependent: :destroy

    enum :sex, { female: "female", male: "male", unspecified: "unspecified" }, default: :unspecified

    validates :given_names, :surname, :date_of_birth, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :assign_slug, on: :create

    def full_name
      "#{given_names} #{surname}"
    end

    private

    # Stable, human-readable id used as the YAML export filename and the
    # scenario-reference key MH-311's scenario catalogue points at.
    def assign_slug
      return if slug.present?

      base = full_name.parameterize
      base = "persona" if base.blank?
      candidate = base
      suffix = 1
      while self.class.exists?(slug: candidate)
        suffix += 1
        candidate = "#{base}-#{suffix}"
      end
      self.slug = candidate
    end
  end
end
