module Timescale
  class JobStats < ActiveRecord::Base
    self.table_name = "timescaledb_information.job_stats"

    belongs_to :job

    attribute :last_run_duration, :string

    scope :success, -> { where(last_run_status: "Success") }
    scope :scheduled, -> { where(job_status: "Scheduled") }
    scope :resume, -> do
      select("sum(total_successes)::int as success,
             sum(total_runs)::int as runs,
             sum(total_failures)::int as failures")
        .to_a.map{|e|e.attributes.transform_keys(&:to_sym) }
    end
  end
end
