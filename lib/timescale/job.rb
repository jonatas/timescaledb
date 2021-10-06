module Timescale
  class Job < ActiveRecord::Base
    self.table_name = "timescaledb_information.jobs"
    self.primary_key = "job_id"

    attribute :schedule_interval, :string
    attribute :max_runtime, :string
    attribute :retry_period, :string

    scope :compression, -> { where(proc_name: "tsbs_compress_chunks") }
    scope :scheduled, -> { where(scheduled: true) }
  end
end
