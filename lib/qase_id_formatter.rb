# frozen_string_literal: true

require "rspec/core/formatters/base_formatter"
require "json"

# MH-314: RSpec's built-in `--format json` drops custom example metadata, so
# a `qase_id:`-tagged example never reaches the report it produces. This
# formatter writes just the qase_id-tagged examples and their outcome,
# consumed by Qase::ResultsReporter / bin/rails qase:report.
#
# Usage: bundle exec rspec --require ./lib/qase_id_formatter \
#          --format QaseIdFormatter --out tmp/qase_results.json --tag qase_id
class QaseIdFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register self, :example_passed, :example_failed, :example_pending, :stop

  def initialize(output)
    super
    @results = []
  end

  def example_passed(notification)  = record(notification.example, "passed")
  def example_failed(notification)  = record(notification.example, "failed", notification.exception&.message)
  def example_pending(notification) = record(notification.example, "skipped", notification.example.execution_result.pending_message)

  def stop(_notification)
    output.write(JSON.generate(@results))
  end

  private

  def record(example, status, comment = nil)
    qase_id = example.metadata[:qase_id]
    return unless qase_id

    @results << { case_id: qase_id, status: status, comment: comment, description: example.full_description }
  end
end
