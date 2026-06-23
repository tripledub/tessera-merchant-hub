# frozen_string_literal: true

class ApplicantPresenter < BasePresenter
  include ContentTags

  presents :applicant

  def status_badge
    colour = case applicant.status
    when "approved" then :green
    when "rejected" then :red
    else :amber
    end
    badge(applicant.status.humanize, colour)
  end

  def principal_count
    applicant.kyc_principals.count
  end

  def document_count
    applicant.kyc_documents.count
  end

  def entity_count
    applicant.corporate_entities.count
  end

  def warning_count
    applicant.validation_warnings.where(acknowledged: false).count
  end

  def total_warning_count
    applicant.validation_warnings.count
  end

  def warning_count_class
    warning_count > 0 ? "text-red-600 dark:text-red-400" : "text-gray-800 dark:text-white/90"
  end

  def detail_rows
    rows = []
    rows << { label: "Company", value: applicant.company_name } if applicant.company_name.present?
    rows << { label: "Email", value: applicant.contact_email } if applicant.contact_email.present?
    rows << { label: "Country", value: applicant.country } if applicant.country.present?
    rows
  end
end
