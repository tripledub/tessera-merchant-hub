# frozen_string_literal: true

module DocumentClassifiers
  class ArticlesOfAssociation < Base
    register handler: :articles_of_association

    def self.pattern
      /articles\s*(of\s*)?association/i
    end
  end
end
