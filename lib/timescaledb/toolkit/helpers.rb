require 'active_record/connection_adapters/postgresql_adapter'

# Useful methods to run TimescaleDB with Toolkit functions in you Ruby app.
module Timescaledb
  # Helpers methods to setup queries that uses the toolkit.
  module Toolkit
    module Helpers

      # Includes toolkit_experimental in the search path to make it easy to have
      # access to all the functions
      def add_toolkit_to_search_path!
        return if schema_search_path.include?("toolkit_experimental")

        self.schema_search_path = "toolkit_experimental, #{schema_search_path}"
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.include(Timescaledb::Toolkit::Helpers)
