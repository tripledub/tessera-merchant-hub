# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comment, type: :model do
  it { is_expected.to belong_to(:commentable) }
  it { is_expected.to belong_to(:author) }
  it { is_expected.to validate_presence_of(:body) }

  it "orders comments chronologically" do
    document = create(:kyc_document)
    author   = create(:user, :psp_admin)

    older = create(:comment, commentable: document, author: author, body: "first", created_at: 2.days.ago)
    newer = create(:comment, commentable: document, author: author, body: "second", created_at: 1.day.ago)

    expect(document.comments.to_a).to eq([ older, newer ])
  end
end
