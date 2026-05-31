require "webmock/rspec"

# Disable real HTTP requests in tests; use WebMock stubs instead.
# Allow localhost for Rails integration tests.
WebMock.disable_net_connect!(allow_localhost: true)
