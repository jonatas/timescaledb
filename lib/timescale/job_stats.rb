module Timescale
  class JobStats < ActiveRecord::Base
    self.table_name = "timescaledb_information.job_stats"

    belongs_to :job

    attribute :last_run_duration, :interval

    scope :success, -> { where(last_run_status: "Success") }
    scope :scheduled, -> { where(job_status: "Scheduled") }
  end
end
