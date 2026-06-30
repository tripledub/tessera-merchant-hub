# frozen_string_literal: true

module DocumentClassifiers
  extend HandlerRegisterable

  Condition = Data.define(:filename, :content_type, :document)

  require_relative "document_classifiers/base"
  require_relative "document_classifiers/passport"
  require_relative "document_classifiers/driving_licence"
  require_relative "document_classifiers/utility_bill"
  require_relative "document_classifiers/certificate_of_incorporation"
  require_relative "document_classifiers/memorandum_of_association"
  require_relative "document_classifiers/articles_of_association"
  require_relative "document_classifiers/certificate_of_amendment"
  require_relative "document_classifiers/certificate_of_directors"
  require_relative "document_classifiers/certificate_of_shareholders"
  require_relative "document_classifiers/share_certificate"
  require_relative "document_classifiers/register_of_members"
  require_relative "document_classifiers/certificate_of_incumbency"
  require_relative "document_classifiers/group_structure_chart"
  require_relative "document_classifiers/certificate_of_registered_address"
  require_relative "document_classifiers/bank_account_statement"
  require_relative "document_classifiers/transaction_extract"
  require_relative "document_classifiers/funds_flow_diagram"
  require_relative "document_classifiers/business_plan"
  require_relative "document_classifiers/apm_summary"
  require_relative "document_classifiers/legal_opinion"
  require_relative "document_classifiers/declaration_of_trust"
  require_relative "document_classifiers/payment_agreement"
  require_relative "document_classifiers/aml_ctf_policy"
  require_relative "document_classifiers/aml_kyc_requirements"
  require_relative "document_classifiers/source_of_wealth_questionnaire"
  require_relative "document_classifiers/aml_ctf_questionnaire"
  require_relative "document_classifiers/ai_fallback"

  self.default = AiFallback
end
