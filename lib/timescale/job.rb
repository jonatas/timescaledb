module Timescale
  class Job < ActiveRecord::Base
    self.table_name = "timescaledb_information.jobs"
    self.primary_key = "job_id"

    scope :compression, -> { where(proc_name: "tsbs_compress_chunks") }
    scope :scheduled, -> { where(scheduled: true) }
  end
end
