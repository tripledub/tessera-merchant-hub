# frozen_string_literal: true

class AddIndexOnAuthorIdToComments < ActiveRecord::Migration[8.1]
  def change
    add_index :comments, :author_id
  end
end
