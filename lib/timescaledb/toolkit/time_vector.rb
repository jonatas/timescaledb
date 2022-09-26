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

        def override_options
          {
            segment_by: segment_by_column,
            time_column: time_column,
            value_column: value_column
          }
        end
        def define_default_scopes
          scope :volatility, -> (columns=segment_by_column) do
            _scope = select([*columns,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> sum() as volatility"
            ].join(", "))
            _scope = _scope.group(columns) if columns
            _scope
          end

          scope :time_weight, -> (columns=segment_by_column) do
            _scope = select([*columns,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> time_weight() as time_weight"
            ].join(", "))
            _scope = _scope.group(columns) if columns
            _scope
          end

          scope :lttb, -> (threshold:, segment_by: segment_by_column, time: time_column, value: value_column) do
            segment = "ordered.#{segment_by_column}"
            lttb_query = <<~SQL
              WITH ordered AS (
                #{select(*segment_by_column, time_column, value_column).order(time_column).to_sql}
              )
              SELECT #{"#{segment}," if segment_by_column}
                (toolkit_experimental.lttb( ordered.#{time_column}, ordered.#{value_column}, #{threshold})
                 -> toolkit_experimental.unnest()).*
              FROM ordered
              #{"GROUP BY device_id" if segment_by_column}
            SQL
            downsampled = unscoped
              .select("#{"#{segment}," if segment_by_column} time as #{time_column}, value as #{value_column}")
              .from("(#{lttb_query}) as ordered")
            if segment_by
              downsampled.inject({}) do |group,e|
                key = e.send(segment_by_column)
                (group[key] ||= []) << [e.send(time_column), e.send(value_column)]
                group
              end
            else
              downsampled.map{|e|[ e[time_column],e[value_column]]}
            end
          end
        end
      end
    end
  end
end

