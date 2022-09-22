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

          scope :lttb, -> (threshold:, **override_options ) do
            lttb_query = <<~SQL
              WITH ordered AS (
                #{select(time_column, value_column).order(time_column).to_sql}
              )
              SELECT toolkit_experimental.lttb(
                ordered.#{time_column},
                ordered.#{value_column},
                #{threshold}) FROM ordered
            SQL
            downsampled = unscoped
              .select("time as #{time_column}, value as #{value_column}")
              .from("toolkit_experimental.unnest((#{lttb_query}))")
              .map{|e|[e[time_column],e[value_column]]}
          end
        end
      end
    end
  end
end

