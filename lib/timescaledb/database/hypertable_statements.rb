module Timescaledb
  class Database
    module HypertableStatements
      # @see https://docs.timescale.com/api/latest/hypertable/hypertable_size/
      #
      # @param [String] hypertable The hypertable to show size of
      # @return [String] The hypertable_size SQL statement
      def hypertable_size_sql(hypertable)
        "SELECT hypertable_size(#{quote(hypertable)});"
      end

      # @see https://docs.timescale.com/api/latest/hypertable/hypertable_detailed_size/
      #
      # @param [String] hypertable The hypertable to show detailed size of
      # @return [String] The hypertable_detailed_size SQL statementh
      def hypertable_detailed_size_sql(hypertable)
        "SELECT * FROM hypertable_detailed_size(#{quote(hypertable)});"
      end

      # @see https://docs.timescale.com/api/latest/hypertable/hypertable_index_size/
      #
      # @param [String] index_name The name of the index on a hypertable
      # @return [String] The hypertable_detailed_size SQL statementh
      def hypertable_index_size_sql(index_name)
        "SELECT hypertable_index_size(#{quote(index_name)});"
      end

      # @see https://docs.timescale.com/api/latest/hypertable/chunks_detailed_size/
      #
      # @param [String] hypertable The name of the hypertable
      # @return [String] The chunks_detailed_size SQL statementh
      def chunks_detailed_size_sql(hypertable)
        "SELECT * FROM chunks_detailed_size(#{quote(hypertable)});"
      end
    end
  end
end
