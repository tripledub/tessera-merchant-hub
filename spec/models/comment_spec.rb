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

  describe "append-only guarantee" do
    it "is readonly once persisted" do
      comment = create(:comment)

      expect(comment).to be_readonly
    end

    it "is not readonly before persistence" do
      comment = build(:comment)

      expect(comment).not_to be_readonly
    end

    it "raises ActiveRecord::ReadOnlyRecord when directly updated" do
      comment = create(:comment)

      expect { comment.update(body: "edited") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord when directly destroyed" do
      comment = create(:comment)

      expect { comment.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    # The guarantee above is narrower than "structural": readonly? blocks
    # .update/.destroy, but Rails' bulk/raw-SQL deletion paths never consult
    # readonly? and so are NOT blocked. These examples pin that actual
    # behavior — they document a known gap, not a desired one. Nothing in
    # this codebase should call these paths directly on Comment; the only
    # sanctioned deletion route is the Commentable dependent: :delete_all
    # cascade when the commentable parent is destroyed.
    it "does not raise when deleted via .delete" do
      comment = create(:comment)

      expect { comment.delete }.not_to raise_error
    end

    it "does not raise when deleted via the association's #delete" do
      document = create(:kyc_document)
      comment  = create(:comment, commentable: document)

      expect { document.comments.delete(comment) }.not_to raise_error
    end

    it "does not raise when the association is cleared via #clear" do
      document = create(:kyc_document)
      create(:comment, commentable: document)

      expect { document.comments.clear }.not_to raise_error
    end

    it "does not raise when the association is replaced" do
      document = create(:kyc_document)
      create(:comment, commentable: document)

      expect { document.comments = [] }.not_to raise_error
    end

    it "does not raise when deleted via Comment.delete_all" do
      create(:comment)

      expect { described_class.delete_all }.not_to raise_error
    end

    it "does not raise when deleted via the association's #delete_all" do
      document = create(:kyc_document)
      create(:comment, commentable: document)

      expect { document.comments.delete_all }.not_to raise_error
    end
  end
end
