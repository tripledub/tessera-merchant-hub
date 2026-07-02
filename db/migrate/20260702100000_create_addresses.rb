class CreateAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :addresses do |t|
      t.string :type, null: false
      t.references :addressable, polymorphic: true, null: false, type: :uuid
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :postcode
      t.string :country, null: false
      t.boolean :primary, null: false, default: false

      t.timestamps
    end

    add_index :addresses, [ :addressable_type, :addressable_id, :type, :primary ],
              unique: true,
              where: '"primary" = true',
              name: "index_addresses_on_addressable_and_type_primary"
  end
end
