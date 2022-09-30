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
            ].join(", "))
              .group(segment_by)
          end

          scope :time_weight, -> (segment_by: segment_by_column) do
            select([*segment_by,
               "timevector(#{time_column}, #{value_column}) -> sort() -> delta() -> abs() -> time_weight() as time_weight"
            ].join(", "))
              .group(segment_by)
          end

          scope :lttb, -> (threshold:, segment_by: segment_by_column, time: time_column, value: value_column) do
            ordered_data = select(*segment_by, time_column, value_column).order(time_column)
            lttb_query = <<~SQL
              WITH ordered AS ( #{ordered_data.to_sql})
              SELECT #{"ordered.#{segment_by}," if segment_by}
                (lttb( ordered.#{time_column}, ordered.#{value_column}, #{threshold})
                 -> toolkit_experimental.unnest()).*
              FROM ordered
              #{"GROUP BY device_id" if segment_by}
            SQL
            downsampled = unscoped
              .select(*segment_by, "time as #{time_column}, value as #{value_column}")
              .from("(#{lttb_query}) as ordered")
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
        end
      end
    end
  end
end

