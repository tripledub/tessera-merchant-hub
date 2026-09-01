# frozen_string_literal: true

module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, -> { order(created_at: :asc).includes(:author) }, as: :commentable, dependent: :delete_all
  end
end
