class AddExecutiveNarrativeToApplicants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :executive_narrative, :jsonb
    add_column :merchants, :executive_narrative_generated_at, :datetime
  end
end
