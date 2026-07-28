# frozen_string_literal: true

module Onboarding
  module ChatCommands
    # Exact-phrase matching only, deliberately: matching substrings inside a normal
    # sentence (e.g. "I want to skip to the good part") would misfire far more often
    # than it would help, so a message must be *just* the command to be detected.
    PHRASES_BY_COMMAND = {
      help: [ "help" ],
      save: [ "save", "save and quit", "save & quit" ],
      skip: [ "skip", "next" ]
    }.freeze

    module_function

    def detect(user_message)
      normalized = normalize(user_message)
      return nil if normalized.blank?

      PHRASES_BY_COMMAND.each do |command, phrases|
        return command if phrases.include?(normalized)
      end

      nil
    end

    def normalize(text)
      text.to_s.strip.downcase.gsub(/[[:punct:]]+\z/, "")
    end
    private_class_method :normalize
  end
end
