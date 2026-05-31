require "pundit/matchers"

RSpec.configure do |config|
  config.include Pundit::Authorization, type: :controller
  config.include Pundit::Matchers, type: :policy
end
