# frozen_string_literal: true

class ApplicantUser < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable

  belongs_to :applicant

  validates :first_name, :last_name, presence: true
end
