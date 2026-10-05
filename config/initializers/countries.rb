# frozen_string_literal: true

# The app is English-only for now, so only load English country names (the gem
# loads every I18n.available_locales by default). Revisit if more locales are added.
ISO3166.configure do |config|
  config.locales = [ :en ]
end
