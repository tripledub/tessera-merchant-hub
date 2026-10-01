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

  RegistryLookupBanner = Data.define(:message, :action_label)

  # Banner for the overview tab, or nil when there is nothing to flag (no company
  # number, or the applicant's own registry lookup succeeded).
  def registry_lookup_banner
    return if applicant.company_number.blank?

    case applicant.registry_lookup_state
    when :never_attempted
      RegistryLookupBanner.new(t("applicants.tabs.overview.registry_lookup.never_attempted"),
                               t("applicants.tabs.overview.registry_lookup.fetch"))
    when :failed
      failed_registry_lookup_banner
    end
  end

  def principal_count
    applicant.kyc_principals.active.count
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

  private

  def failed_registry_lookup_banner
    retry_label = t("applicants.tabs.overview.registry_lookup.retry") if applicant.registry_lookup_retryable?

    message = case applicant.registry_lookup_error
    when "rate_limited", "unavailable" then t("applicants.tabs.overview.registry_lookup.transient")
    when "not_found", "invalid_number" then t("applicants.tabs.overview.registry_lookup.wrong_number")
    else t("applicants.tabs.overview.registry_lookup.unsupported")
    end

    RegistryLookupBanner.new(message, retry_label)
  end
end
