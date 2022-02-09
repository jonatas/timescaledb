class CreateScorePerHours < ActiveRecord::Migration[7.0]
  def change
    create_scenic_continuous_aggregate :score_per_hours
  end
end
