require_relative 'chunk'
module Timescale
  module HypertableHelpers
    extend ActiveSupport::Concern

    included do
      scope :chunks, -> () do
        Chunk.where(hypertable_name: self.table_name)
      end

      scope :last_month, -> { where('created_at > ?', 1.month.ago) }
      scope :last_week, -> { where('created_at > ?', 1.week.ago) }
      scope :last_hour, -> { where('created_at > ?', 1.hour.ago) }
      scope :yesterday, -> { where('DATE(created_at) = ?', 1.day.ago.to_date) }
      scope :today, -> { where('DATE(created_at) = ?', Date.today) }

      scope :counts_per, -> (time_dimension) {
        select("time_bucket('#{time_dimension}', created_at) as time, identifier, count(1) as total")
          .group(:time, :identifier).order(:time)
          .map {|result| [result.time, result.identifier, result.total]}
      }

      scope :detailed_size, -> do
        self.connection.execute("SELECT * from chunks_detailed_size('#{self.table_name}')")
          .map(&OpenStruct.method(:new))
      end

      scope :compression_stats, -> do
        self.connection.execute("SELECT * from hypertable_compression_stats('#{self.table_name}')")
          .map(&OpenStruct.method(:new))
      end
    end
  end
end
