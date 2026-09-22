# frozen_string_literal: true

module Qase
  # MH-314: reports RSpec results tagged with `qase_id:` metadata into the
  # Qase MH project via its plain REST API — there is no official Ruby/RSpec
  # reporter (checked). Reads the JSON report QaseIdFormatter produces,
  # creates a run, and posts one result per qase_id-tagged example.
  #
  # Used by bin/rails qase:report, not by the specs themselves: running
  # `bundle exec rspec` never needs QASE_API_TOKEN or makes a network call —
  # reporting is a separate, explicit step.
  class ResultsReporter
    class Error < StandardError; end

    BASE_URL = "https://api.qase.io/v1"
    PROJECT_CODE = "MH"

    def self.call(...) = new(...).call

    def initialize(report_path:, run_title:, api_token: ENV.fetch("QASE_API_TOKEN", nil))
      @report_path = report_path
      @run_title = run_title
      @api_token = api_token
    end

    def call
      raise Error, "QASE_API_TOKEN is not set" if @api_token.blank?
      raise Error, "No report at #{@report_path} — run rspec with QaseIdFormatter first" unless File.exist?(@report_path)

      results = JSON.parse(File.read(@report_path)).map(&:symbolize_keys)
      raise Error, "No qase_id-tagged examples found in #{@report_path}" if results.empty?

      run_id = create_run(results.map { |r| r.fetch(:case_id) }.uniq)
      post_results(run_id, results)
      run_id
    end

    private

    def create_run(case_ids)
      response = post("/run/#{PROJECT_CODE}", { title: @run_title, cases: case_ids, is_autotest: true })
      response.fetch("result").fetch("id")
    end

    def post_results(run_id, results)
      body = {
        results: results.map { |r| { case_id: r.fetch(:case_id), status: r.fetch(:status), comment: r[:comment] } }
      }
      post("/result/#{PROJECT_CODE}/#{run_id}/bulk", body)
    end

    def post(path, body)
      uri = URI.parse("#{BASE_URL}#{path}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Token" => @api_token)
      request.body = body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      parsed = JSON.parse(response.body)
      raise Error, "Qase API error (#{path}): #{parsed}" unless response.is_a?(Net::HTTPSuccess) && parsed["status"]

      parsed
    end
  end
end
