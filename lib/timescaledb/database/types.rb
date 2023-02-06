module Timescaledb
  class Database
    module Types
      # @param [String] interval The interval value
      # @return [String]
      def interval_to_sql(interval)
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
