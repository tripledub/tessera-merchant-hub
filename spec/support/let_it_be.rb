require "test_prof/recipes/rspec/let_it_be"

TestProf::LetItBe.configure do |config|
  # Reload models by default so each example gets a fresh instance backed by
  # the shared record (avoids stale in-memory state leaking between examples).
  config.default_modifiers[:reload] = true
end
