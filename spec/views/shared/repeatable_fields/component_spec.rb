require "rails_helper"

RSpec.describe "shared/repeatable_fields/_component", type: :view do
  let(:application_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attr_accessor :items

      def items_attributes=(_attributes); end

      def self.model_name
        ActiveModel::Name.new(self, nil, "TestApplication")
      end
    end
  end
  let(:item_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :id, :string
      attribute :name, :string

      def persisted?
        id.present?
      end

      def self.model_name
        ActiveModel::Name.new(self, nil, "TestItem")
      end
    end
  end
  let(:application) { application_class.new(items: items) }
  let(:items) do
    [
      item_class.new(id: "existing-id", name: "first.example"),
      item_class.new(name: "second.example")
    ]
  end
  let(:fields_renderer) do
    lambda do |form|
      form.text_field(:name) +
        form.object.errors.full_messages_for(:name).map { |message| content_tag(:p, message, class: "form-error") }.join.html_safe
    end
  end

  before do
    items.second.errors.add(:name, "is unavailable")

    I18n.with_locale(:en) do
      render inline: <<~ERB, locals: { application: application, item_class: item_class, fields_renderer: fields_renderer }
        <%= form_with model: application, url: "/applications" do |form| %>
          <%= render "shared/repeatable_fields/component",
                form: form,
                association: :items,
                new_child: item_class.new,
                fields_partial: nil,
                fields_renderer: fields_renderer,
                add_label: "Add domain",
                remove_label: "Remove domain",
                min: 1,
                max: 3 %>
        <% end %>
      ERB
    end
  end

  it "renders existing nested records and keeps errors with their item" do
    expect(rendered.scan('data-repeatable-fields-target="item"').size).to eq(3)
    expect(rendered).to have_field("test_application[items_attributes][0][name]", with: "first.example")
    expect(rendered).to have_field("test_application[items_attributes][1][name]", with: "second.example")
    expect(rendered).to have_field("test_application[items_attributes][0][id]", with: "existing-id", type: :hidden)

    second_item = Capybara.string(rendered).find_all("[data-repeatable-fields-target='item']")[1]
    expect(second_item).to have_css(".form-error", text: "Name is unavailable")
  end

  it "provides a new-record template for the Stimulus controller" do
    expect(rendered).to include('data-repeatable-fields-target="template"')
    expect(rendered).to include("NEW_RECORD")
    expect(rendered).to include("test_application[items_attributes][NEW_RECORD][name]")
  end

  it "wires accessible controls and the configured limits" do
    expect(rendered).to include('data-controller="repeatable-fields"')
    expect(rendered).to include('data-repeatable-fields-min-value="1"')
    expect(rendered).to include('data-repeatable-fields-max-value="3"')
    expect(rendered).to include('data-repeatable-fields-added-message-value="Item added"')
    expect(rendered).to include('data-repeatable-fields-removed-message-value="Item removed"')
    expect(rendered).to have_button("Add domain", type: "button")
    expect(rendered.scan('data-repeatable-fields-target="remove"').size).to eq(3)
    expect(rendered).to have_css("[aria-live='polite'][data-repeatable-fields-target='status']", visible: :all)
  end
end
