# frozen_string_literal: true

# MH-391: what kind of company an applicant is (limited company, sole trader...),
# asked by the chat. It decides whether a registry lookup applies. Until now it
# only existed as free text in the chat's session data.
class AddCompanyTypeToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :company_type, :string
  end
end
