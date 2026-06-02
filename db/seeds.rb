demo_password = ENV.fetch("DEMO_USER_PASSWORD", "password123!")
demo_merchant_id = ENV.fetch("DEMO_MERCHANT_ID", "merch_demo")

demo_users = [
  { email: "psp-admin@tessera.test", role: :psp_admin, merchant_id: nil },
  { email: "psp-support@tessera.test", role: :psp_support, merchant_id: nil },
  { email: "merchant-admin@tessera.test", role: :merchant_admin, merchant_id: demo_merchant_id },
  { email: "merchant-viewer@tessera.test", role: :merchant_viewer, merchant_id: demo_merchant_id }
]

demo_users.each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.assign_attributes(
    password: demo_password,
    role: attrs[:role],
    merchant_id: attrs[:merchant_id]
  )
  user.save!
end

puts "Seeded #{demo_users.size} demo users. Password: #{demo_password}"
puts "Merchant demo users are linked to merchant_id=#{demo_merchant_id}."
puts "Core-owned merchants, shops, payments, credentials, and audit data are seeded by tessera-core."
