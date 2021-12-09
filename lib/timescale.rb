require 'active_record'

require_relative 'timescale/acts_as_hypertable'
require_relative 'timescale/acts_as_hypertable/core'
require_relative 'timescale/chunk'
require_relative 'timescale/compression_settings'
require_relative 'timescale/continuous_aggregates'
require_relative 'timescale/dimensions'
require_relative 'timescale/hypertable'
require_relative 'timescale/job'
require_relative 'timescale/job_stats'
require_relative 'timescale/schema_dumper'
require_relative 'timescale/stats_report'
require_relative 'timescale/migration_helpers'
require_relative 'timescale/version'

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

  def stats(scope=Hypertable.all)
    StatsReport.resume(scope)
  end

  def default_hypertable_options
    Timescale::ActsAsHypertable::DEFAULT_OPTIONS
  end
end

begin
  require 'scenic'
  require_relative 'timescale/scenic/adapter'

  Scenic.configure do |config|
    config.database = Timescale::Scenic::Adapter.new
  end
rescue LoadError
  # This is expected when the scenic gem is not being used
end
