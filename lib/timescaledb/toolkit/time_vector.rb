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
        end
      end
    end
  end
end

