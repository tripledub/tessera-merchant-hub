# frozen_string_literal: true

require "zip"

module Synthetic
  # MH-311: bundles every document a scenario's people generate into a
  # single zip, so a tester can download one file instead of generating each
  # persona's documents by hand through MH-309's admin page.
  class ScenarioDocumentPack
    def self.call(scenario)
      new(scenario).call
    end

    def initialize(scenario)
      @scenario = scenario
    end

    def call
      buffer = Zip::OutputStream.write_buffer do |zip|
        @scenario.people.each do |person|
          persona = person.persona
          person.documents.each do |document|
            generator = Kyc::Synthetic::DocumentGenerators.for(document.type)
            pdf_data = generator.call(persona: persona, options: document.options)
            zip.put_next_entry("#{persona.slug}-#{document.type}.pdf")
            zip.write(pdf_data)
          end
        end
      end
      buffer.rewind
      buffer.read
    end
  end
end
