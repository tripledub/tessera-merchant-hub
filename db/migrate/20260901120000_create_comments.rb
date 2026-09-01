# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :commentable_type, null: false
      t.uuid :commentable_id, null: false
      t.bigint :author_id, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, %i[commentable_type commentable_id]
    add_foreign_key :comments, :users, column: :author_id
  end
end
