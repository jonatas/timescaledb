require "timescale/version"
require 'active_record'
require_relative 'timescale/chunk'
require_relative 'timescale/hypertable'
require_relative 'timescale/job'
require_relative 'timescale/job_stats'
require_relative 'timescale/stats_report'
require_relative 'timescale/continuous_aggregates'
require_relative 'timescale/compression_settings'
require_relative 'timescale/hypertable_helpers'
require_relative 'timescale/migration_helpers'

module Timescale
  module_function
  def chunks
    Chunk.all
  end

  def hypertables
    Hypertable.all
  end

  def continuous_aggregates
    ContinuousAggregates.all
  end

  def compression_settings
    CompressionSettings.all
  end

  def jobs
    Job.all
  end

  def job_stats
    JobStats.all
  end

  def show_stats
    StatsReport.resume
  end
end
