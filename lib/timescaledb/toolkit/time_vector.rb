# frozen_string_literal: true

module Timescaledb
  module Toolkit
    module TimeVector
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def value_column
          @value_column ||= time_vector_options[:value_column] || :val
        end

        def time_column
          respond_to?(:time_column) && super || time_vector_options[:time_column] 
        end
        def segment_by_column
          time_vector_options[:segment_by]
        end

        protected

        def define_default_scopes
          scope :volatility, -> (segment_by: segment_by_column) do
            select([*segment_by,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> sum() as volatility"
            ].join(", ")).group(segment_by)
          end

          scope :time_weight, -> (segment_by: segment_by_column) do
            select([*segment_by,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> time_weight() as time_weight"
            ].join(", "))
              .group(segment_by)
          end

          scope :lttb, -> (threshold:, segment_by: segment_by_column, time: time_column, value: value_column) do
            lttb_query = <<~SQL
              WITH x AS ( #{select(*segment_by, time_column, value_column).to_sql})
              SELECT #{"x.#{segment_by}," if segment_by}
                (lttb( x.#{time_column}, x.#{value_column}, #{threshold})
                 -> toolkit_experimental.unnest()).*
              FROM x
              #{"GROUP BY device_id" if segment_by}
            SQL
            downsampled = unscoped
              .select(*segment_by, "time as #{time_column}, value as #{value_column}")
              .from("(#{lttb_query}) as x")
            if segment_by
              downsampled.inject({}) do |group,e|
                key = e.send(segment_by)
                (group[key] ||= []) << [e.send(time_column), e.send(value_column)]
                group
              end
            else
              downsampled.map{|e|[ e[time_column],e[value_column]]}
            end
          end

          scope :ohlc, -> (timeframe: '1h', segment_by: segment_by_column, time: time_column, value: value_column) do
            ohlc = select(*segment_by,
                          "time_bucket('#{timeframe}',#{time}) as #{time},
                           toolkit_experimental.ohlc(#{time}, #{value})")
              .group(*(segment_by ? [1,2] : 1))

            unscoped
              .from("(#{ohlc.to_sql}) AS ohlc")
              .select(*segment_by, time,
               "toolkit_experimental.open(ohlc),
                toolkit_experimental.high(ohlc),
                toolkit_experimental.low(ohlc),
                toolkit_experimental.close(ohlc),
                toolkit_experimental.open_time(ohlc),
                toolkit_experimental.high_time(ohlc),
                toolkit_experimental.low_time(ohlc),
                toolkit_experimental.close_time(ohlc)")
          end
        end
      end
    end
  end
end

