# frozen_string_literal: true

FactoryBot.define do
  factory :tessera_audit_event, class: "Tessera::AuditEvent" do
    id { SecureRandom.uuid }
    association :payment, factory: :tessera_payment
    event_type { "authorisation" }
    actor { "system" }
    outcome { "success" }
    metadata { {} }
    occurred_at { Time.current }

    # Bypass readonly? guard — test data only; production tables are owned by tessera-core
    to_create do |instance|
      attrs = instance.attributes.except("payment").compact
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v|
        v.is_a?(Hash) ? ActiveRecord::Base.connection.quote(v.to_json) : ActiveRecord::Base.connection.quote(v)
      }.join(", ")
      ActiveRecord::Base.connection.execute(
        "INSERT INTO audit_events (#{cols}) VALUES (#{vals})"
      )
      instance.instance_variable_set(:@new_record, false)
      instance
    end
  end
end
