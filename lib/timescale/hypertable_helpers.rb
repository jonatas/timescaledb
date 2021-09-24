require_relative 'chunk'
require_relative 'hypertable'
module Timescale
  module HypertableHelpers
    extend ActiveSupport::Concern

    included do
      scope :chunks, -> () do
        Chunk.where(hypertable_name: self.table_name)
      end

      scope :hypertable, -> () do
        Hypertable.find_by(hypertable_name: self.table_name)
      end

      scope :jobs, -> () do
        Job.where(hypertable_name: self.table_name)
      end

      scope :job_stats, -> () do
        JobStats.where(hypertable_name: self.table_name)
      end

      scope :compression_settings, -> () do
        CompressionSettings.where(hypertable_name: self.table_name)
      end

      scope :continuous_aggregates, -> () do
        ContinuousAggregates.where(hypertable_name: self.table_name)
      end

      scope :last_month, -> { where('created_at > ?', 1.month.ago) }
      scope :last_week, -> { where('created_at > ?', 1.week.ago) }
      scope :last_hour, -> { where('created_at > ?', 1.hour.ago) }
      scope :yesterday, -> { where('DATE(created_at) = ?', 1.day.ago.to_date) }
      scope :today, -> { where('DATE(created_at) = ?', Date.today) }
    end
  end
end
