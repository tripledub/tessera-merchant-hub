# frozen_string_literal: true

class Kyc::ApplicantDomainsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) if params[:applicant_id] }
  expose(:applicant_domain) { params[:id] ? ApplicantDomain.find(params[:id]) : ApplicantDomain.new(applicant: applicant) }

  def new
    authorize applicant_domain
  end

  def create
    authorize applicant_domain
    added = Kyc::AddDomainByHand.call(
      domain: applicant_domain,
      name: applicant_domain_params[:name],
      justification: applicant_domain_params[:justification],
      author: current_user
    )

    if added
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to applicant_path(applicant_domain.applicant), notice: t("flash.applicant_domains.create_success") }
      end
    else
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    authorize applicant_domain
    applicant = applicant_domain.applicant
    applicant_domain.destroy!
    redirect_to applicant_path(applicant), notice: t("flash.applicant_domains.destroy_success")
  end

  # The comment form shown when accepting a domain that has no evidence (MH-300).
  def accept_form
    authorize applicant_domain
  end

  def accept
    authorize applicant_domain
    accepted = Kyc::AcceptDomain.call(
      domain: applicant_domain,
      reviewer: current_user,
      comment_body: params.dig(:comment, :body)
    )

    if accepted
      respond_with_row(t("flash.applicant_domains.accepted"), clear_modal: true)
    else
      render :accept_form, formats: :html, status: :unprocessable_content
    end
  end

  def reject
    authorize applicant_domain
    applicant_domain.update!(review_status: :rejected)
    respond_with_row(t("flash.applicant_domains.rejected"))
  end

  private

  def respond_with_row(notice, clear_modal: false)
    fresh = ApplicantDomain.includes(:comments, evidence_links: { kyc_document: { file_attachment: :blob } })
                           .find(applicant_domain.id)

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.replace(fresh, partial: "kyc/applicant_domains/domain_row", locals: { applicant_domain: fresh }) ]
        streams << turbo_stream.update("applicant-domain-modal", "") if clear_modal
        render turbo_stream: streams
      end
      format.html { redirect_to applicant_path(fresh.applicant), notice: notice }
    end
  end

  def applicant_domain_params
    params.require(:applicant_domain).permit(:name, :justification)
  end
end
