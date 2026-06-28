# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Production solid adapter schemas" do # rubocop:disable RSpec/DescribeClass
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

  it "loads Action Cable from the dedicated cable database in production" do
    cable_config = File.read(File.join(root, "config/cable.yml"))

    expect(cable_config).to include("adapter: solid_cable")
    expect(cable_config).to include("writing: cable")
    expect(cable_config).not_to include("adapter: redis")
  end

  it "defines the messages table required for Turbo Stream broadcasts" do
    cable_schema = File.read(File.join(root, "db/cable_schema.rb"))

    expect(cable_schema).to include('create_table "solid_cable_messages"')
  end
end
