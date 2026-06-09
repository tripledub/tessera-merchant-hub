# frozen_string_literal: true

# =============================================================================
# Seeds::Payment
# Bypasses ReadOnlyRecord so we can write fake payments in development.
# This class is ONLY defined here and is NEVER autoloaded.
# =============================================================================
class Seeds
  class Payment < ApplicationRecord
    self.table_name = "payments"
  end
end

# =============================================================================
# PSP demo users  —  seed in ALL environments
# =============================================================================
demo_password    = ENV.fetch("DEMO_USER_PASSWORD", "password123!")
demo_merchant_id = ENV.fetch("DEMO_MERCHANT_ID", "merch_demo")

psp_users = [
  { email: "psp-admin@tessera.test",      role: :psp_admin,       merchant_id: nil },
  { email: "psp-support@tessera.test",    role: :psp_support,     merchant_id: nil },
  { email: "merchant-admin@tessera.test", role: :merchant_admin,  merchant_id: demo_merchant_id },
  { email: "merchant-viewer@tessera.test", role: :merchant_viewer, merchant_id: demo_merchant_id }
]

psp_users.each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.assign_attributes(password: demo_password, role: attrs[:role], merchant_id: attrs[:merchant_id])
  user.save!
end

puts "Seeded #{psp_users.size} PSP demo users. Password: #{demo_password}"

# =============================================================================
# Faker-generated merchants, shops, users, and payments  —  development ONLY
# =============================================================================
if Rails.env.development?
  require "faker"

  MERCHANT_COUNTRIES = %w[GB DE FR NL IE].freeze
  SHOP_CURRENCIES    = %w[GBP GBP GBP EUR EUR USD].freeze

  PAYMENT_STATUSES = {
    "succeeded" => 60,
    "failed"    => 15,
    "pending"   => 10,
    "refunded"  => 10,
    "voided"    =>  5
  }.freeze

  # ----- Merchants -----------------------------------------------------------
  merchant_seeds = [
    { name: "Evergreen Retail Ltd",   company_name: "Evergreen Holdings",   country: "GB" },
    { name: "Nordic Goods GmbH",      company_name: "Nordic Commerce GmbH", country: "DE" },
    { name: "Élan Boutique SAS",      company_name: "Élan Group SAS",       country: "FR" },
    { name: "Polder Stores BV",       company_name: "Polder Commerce BV",   country: "NL" },
    { name: "Celtic Cart Limited",    company_name: "Celtic Commerce Ltd",  country: "IE" }
  ]

  merchants = merchant_seeds.map.with_index(1) do |attrs, i|
    mid = "merch_fake_%02d" % i
    m = Merchant.find_or_initialize_by(merchant_id: mid)
    m.assign_attributes(name: attrs[:name], company_name: attrs[:company_name], country: attrs[:country])
    m.save!
    m
  end

  puts "Seeded #{merchants.size} fake merchants."

  # ----- Shops ---------------------------------------------------------------
  shops_created = 0

  merchants.each_with_index do |merchant, mi|
    shop_count = (mi % 2 == 0) ? 3 : 2

    shop_count.times do |si|
      sid = "shop_fake_%02d_%02d" % [ mi + 1, si + 1 ]
      shop = Shop.find_or_initialize_by(shop_id: sid)
      shop.assign_attributes(
        merchant_id:            merchant.merchant_id,
        integration_account_id: "ia_fake_%02d_%02d" % [ mi + 1, si + 1 ],
        name:                   si == 0 ? "#{merchant.name} – Main" : "#{merchant.name} – EU #{si}",
        country:                merchant.country,
        test_mode:              si != 0,
        notification_url:       si == 0 ? "https://#{merchant.name.downcase.gsub(/\W+/, "-")}.example.com/webhooks" : nil
      )
      shop.save!
      shops_created += 1
    end
  end

  puts "Seeded #{shops_created} fake shops."

  # ----- Users ---------------------------------------------------------------
  users_created = 0

  merchants.each_with_index do |merchant, mi|
    domain = "merchant-#{mi + 1}.example.com"

    [
      { email: "admin@#{domain}",  role: :merchant_admin,  merchant_id: merchant.merchant_id },
      { email: "viewer@#{domain}", role: :merchant_viewer, merchant_id: merchant.merchant_id }
    ].each do |attrs|
      user = User.find_or_initialize_by(email: attrs[:email])
      user.assign_attributes(password: demo_password, role: attrs[:role], merchant_id: attrs[:merchant_id])
      user.save!
      users_created += 1
    end
  end

  puts "Seeded #{users_created} fake merchant users. Password: #{demo_password}"

  # ----- Demo status users for QA (Evergreen Retail Ltd / merch_fake_01) -----
  # These users are on merchant-1 so you can see all three status badges on
  # the Team page when signed in as admin@merchant-1.example.com
  demo_merchant = merchants.first

  [
    { email: "locked@merchant-1.example.com",      role: :merchant_viewer, state: :locked },
    { email: "deactivated@merchant-1.example.com", role: :merchant_viewer, state: :deactivated },
    { email: "viewer2@merchant-1.example.com",     role: :merchant_viewer, state: :active }
  ].each do |attrs|
    user = User.find_or_initialize_by(email: attrs[:email])
    user.assign_attributes(
      password:    demo_password,
      role:        attrs[:role],
      merchant_id: demo_merchant.merchant_id,
      deactivated_at: nil,
      locked_at:      nil,
      unlock_token:   nil
    )
    user.save!

    case attrs[:state]
    when :locked
      user.lock_access!(send_instructions: false) unless user.access_locked?
    when :deactivated
      unless user.deactivated?
        user.update_columns(deactivated_at: 2.days.ago)
        user.lock_access!(send_instructions: false) unless user.access_locked?
      end
    end
  end

  puts "Seeded 3 QA demo users on #{demo_merchant.name} (active, locked, deactivated)."
  puts "  Sign in as admin@merchant-1.example.com to see all three status badges on /team"

  # ----- Payments ------------------------------------------------------------
  Seeds::Payment.delete_all

  total_payments = 0
  now = Time.current
  window = 90.days

  Shop.where("shop_id LIKE 'shop_fake_%'").find_each do |shop|
    rows = []

    PAYMENT_STATUSES.each do |status, count|
      count.times do
        inserted = now - rand(window)
        rows << {
          shop_id:            shop.shop_id,
          status:             status,
          amount:             rand(1_000..500_000),
          currency:           SHOP_CURRENCIES.sample,
          idempotency_key:    SecureRandom.uuid,
          merchant_reference: rand < 0.7 ? "ORD-#{SecureRandom.hex(4).upcase}" : nil,
          inserted_at:        inserted,
          updated_at:         inserted
        }
      end
    end

    rows.sort_by! { |r| r[:inserted_at] }
    Seeds::Payment.insert_all!(rows)
    total_payments += rows.size
  end

  puts "Seeded #{total_payments} fake payments across #{Shop.where("shop_id LIKE 'shop_fake_%'").count} shops."
  puts ""
  puts "Sign in as any merchant user with password: #{demo_password}"
  puts "  admin@merchant-1.example.com  →  Evergreen Retail Ltd (merchant_admin)"
  puts "  admin@merchant-2.example.com  →  Nordic Goods GmbH (merchant_admin)"
  puts "  admin@merchant-3.example.com  →  Élan Boutique SAS (merchant_admin)"
  puts "  admin@merchant-4.example.com  →  Polder Stores BV (merchant_admin)"
  puts "  admin@merchant-5.example.com  →  Celtic Cart Limited (merchant_admin)"
end
