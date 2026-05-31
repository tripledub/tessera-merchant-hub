RSpec.configure do |config|
  config.include Pundit::Authorization, type: :controller
end
