module Timescaledb
  class Job < ActiveRecord::Base
    self.table_name = "timescaledb_information.jobs"
    self.primary_key = "job_id"

    scope :compression, -> { where(proc_name: [:tsbs_compress_chunks, :policy_compression]) }
    scope :refresh_continuous_aggregate, -> { where(proc_name: :policy_refresh_continuous_aggregate) }
    scope :scheduled, -> { where(scheduled: true) }
  end
end
