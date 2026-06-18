# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_18_162155) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "kyc_documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "applicant_id", null: false
    t.datetime "created_at", null: false
    t.uuid "kyc_principal_id"
    t.decimal "match_confidence", precision: 4, scale: 3
    t.string "match_method"
    t.jsonb "result"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["applicant_id"], name: "index_kyc_documents_on_applicant_id"
    t.index ["kyc_principal_id"], name: "index_kyc_documents_on_kyc_principal_id"
  end

  create_table "kyc_principals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.uuid "applicant_id", null: false
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.string "email"
    t.string "name", null: false
    t.string "postcode"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["applicant_id"], name: "index_kyc_principals_on_applicant_id"
  end

  create_table "merchants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1"
    t.string "city"
    t.string "company_name"
    t.string "contact_email"
    t.string "country"
    t.string "country_code"
    t.datetime "created_at", null: false
    t.string "merchant_id"
    t.string "name", null: false
    t.string "status", default: "pending", null: false
    t.string "support_url"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_merchants_on_merchant_id", unique: true, where: "(merchant_id IS NOT NULL)"
    t.index ["type"], name: "index_merchants_on_type"
  end

  create_table "shops", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "country"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "integration_account_id", null: false
    t.string "merchant_id", null: false
    t.string "name", null: false
    t.string "notification_url"
    t.string "shop_id", null: false
    t.boolean "test_mode", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["integration_account_id"], name: "index_shops_on_integration_account_id"
    t.index ["merchant_id"], name: "index_shops_on_merchant_id"
    t.index ["shop_id"], name: "index_shops_on_shop_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.datetime "deactivated_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "merchant_id"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.integer "sign_in_count", default: 0, null: false
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["deactivated_at"], name: "index_users_on_deactivated_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["merchant_id"], name: "index_users_on_merchant_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "kyc_documents", "kyc_principals"
  add_foreign_key "kyc_documents", "merchants", column: "applicant_id"
  add_foreign_key "kyc_principals", "merchants", column: "applicant_id"
end
