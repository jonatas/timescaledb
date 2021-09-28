require "active_support/core_ext/numeric/conversions"
module Timescale
  module StatsReport
    module_function
    def resume
      {
        hypertables: {
          count: Hypertable.count,
          uncompressed: Hypertable.all.to_a.count { |h| h.compression_stats.empty? },
          chunks: {
            total: Chunk.count,
            compressed: Chunk.compressed.count,
            uncompressed: Chunk.uncompressed.count
          },
          size: {
            before_compressing: Hypertable.all.map{|h|h.before_total_bytes}.inject(:+).to_s(:human_size),
            after_compressing: Hypertable.all.map{|h|h.after_total_bytes}.inject(:+).to_s(:human_size)
          }
        },
        continuous_aggregates: { count: ContinuousAggregates.count },
        jobs_stats: JobStats.resume
      }
    end
  end
end
