class Play < ApplicationRecord
  belongs_to :game

  self.primary_key = "created_at"

  acts_as_hypertable
end
