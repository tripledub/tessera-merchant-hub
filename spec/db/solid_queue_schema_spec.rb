# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Solid Queue production schema" do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path("../..", __dir__) }

  it "loads Solid Queue from the dedicated queue database in production" do
    production_config = File.read(File.join(root, "config/environments/production.rb"))

    expect(production_config).to include("config.active_job.queue_adapter = :solid_queue")
    expect(production_config).to include("config.solid_queue.connects_to = { database: { writing: :queue } }")
  end

  it "defines the process table required when the Puma Solid Queue plugin boots" do
    queue_schema = File.read(File.join(root, "db/queue_schema.rb"))

    expect(queue_schema).to include('create_table "solid_queue_processes"')
  end
end
