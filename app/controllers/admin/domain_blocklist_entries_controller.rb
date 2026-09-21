# frozen_string_literal: true

class Admin::DomainBlocklistEntriesController < ApplicationController
  def index
    authorize DomainBlocklistEntry
    load_entries
    @entry = DomainBlocklistEntry.new
  end

  def create
    authorize DomainBlocklistEntry
    @entry = DomainBlocklistEntry.new

    if Kyc::AddBlocklistEntry.call(entry: @entry, name: entry_params[:name], author: current_user)
      redirect_to admin_domain_blocklist_entries_path,
        notice: t("flash.admin.domain_blocklist_entries.added", name: @entry.name)
    else
      load_entries
      render :index, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    entry = DomainBlocklistEntry.find(params[:id])
    authorize entry
    entry.destroy!
    redirect_to admin_domain_blocklist_entries_path,
      notice: t("flash.admin.domain_blocklist_entries.removed", name: entry.name)
  end

  private

  def load_entries
    @entries = DomainBlocklistEntry.includes(:created_by).order(:name)
  end

  def entry_params
    params.fetch(:domain_blocklist_entry, {}).permit(:name)
  end
end
