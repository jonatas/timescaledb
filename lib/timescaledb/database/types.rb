module Timescaledb
  class Database
    module Types
      # @param [String, Integer] interval The interval value
      # @return [String]
      def interval_to_sql(interval)
        return 'NULL' if interval.nil?
        return interval if interval.kind_of?(Integer)

        "INTERVAL #{quote(interval)}"
      end

      # @param [String] boolean The boolean value
      # @return [String]
      def boolean_to_sql(boolean)
        quote(boolean ? 'TRUE' : 'FALSE')
      end
    end
  end
end
