# frozen_string_literal: true

class ApplicantUser < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :applicant
end
