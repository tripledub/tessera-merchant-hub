# frozen_string_literal: true

require "rails_helper"

class RepeatableFieldsPreviewItem
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :id, :string
  attribute :name, :string

  def persisted?
    id.present?
  end

  def self.model_name
    ActiveModel::Name.new(self, nil, "PreviewItem")
  end
end

class RepeatableFieldsPreviewApplication
  include ActiveModel::Model

  attr_accessor :items

  def items_attributes=(_attributes); end

  def self.model_name
    ActiveModel::Name.new(self, nil, "PreviewApplication")
  end
end

class RepeatableFieldsPreviewController < ActionController::Base
  def show
    application = RepeatableFieldsPreviewApplication.new(
      items: [ RepeatableFieldsPreviewItem.new(id: "persisted-id", name: "Existing item") ]
    )
    fields_renderer = ->(form) { form.text_field(:name) }

    render inline: <<~ERB, layout: false, locals: { application: application, fields_renderer: fields_renderer }
      <!doctype html>
      <html>
        <head><%= javascript_importmap_tags %></head>
        <body>
          <%= form_with model: application, url: "#" do |form| %>
            <%= render "shared/repeatable_fields/component",
                  form: form,
                  association: :items,
                  new_child: RepeatableFieldsPreviewItem.new,
                  fields_partial: nil,
                  fields_renderer: fields_renderer,
                  add_label: "Add item",
                  remove_label: "Remove item",
                  min: 1,
                  max: 2 %>
          <% end %>
        </body>
      </html>
    ERB
  end
end

RSpec.describe "Repeatable fields", type: :system do
  it "adds and removes new and persisted items while enforcing configured limits" do
    visit "/repeatable-fields-preview"

    persisted_item = page.find("[data-repeatable-fields-target='item']")
    expect(persisted_item).to have_button("Remove item", disabled: true)

    click_button "Add item"

    visible_items = page.all("[data-repeatable-fields-target='item']")
    expect(visible_items.size).to eq(2)
    expect(page).to have_button("Add item", disabled: true)
    expect(visible_items.last.find("input[type='text']")[:name]).not_to include("NEW_RECORD")
    expect(page.evaluate_script("document.activeElement.name")).to eq(visible_items.last.find("input[type='text']")[:name])

    within(visible_items.last) { click_button "Remove item" }
    expect(page.all("[data-repeatable-fields-target='item']").size).to eq(1)
    expect(page).to have_button("Add item", disabled: false)

    click_button "Add item"
    within(page.all("[data-repeatable-fields-target='item']").first) { click_button "Remove item" }

    all_items = page.all("[data-repeatable-fields-target='item']", visible: :all)
    expect(all_items.first).not_to be_visible
    expect(all_items.first.find("input[name*='[_destroy]']", visible: :all).value).to eq("1")
    expect(page.all("[data-repeatable-fields-target='item']").first).to have_button("Remove item", disabled: true)
  end
end
