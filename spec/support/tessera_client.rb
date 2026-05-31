# Ensure TesseraCoreClient can be instantiated in tests.
# Actual HTTP calls are blocked by WebMock — this just satisfies ENV.fetch.
ENV["TESSERA_CORE_URL"] ||= "http://tessera-core.test"
ENV["TESSERA_INTERNAL_API_KEY"] ||= "test-internal-key"
