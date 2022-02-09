require 'scenic/adapters/postgres'
require 'scenic/adapters/postgres/views'

module Timescale
  module Scenic
    class Views < ::Scenic::Adapters::Postgres::Views
      # All of the views that this connection has defined, excluding any
      # Timescale continuous aggregates. Those should be defined using
      # +create_continuous_aggregate+ rather than +create_view+.
      #
      # @return [Array<Scenic::View>]
      def all
        ts_views = views_from_timescale.map { |v| to_scenic_view(v) }
        pg_views = views_from_postgres.map { |v| to_scenic_view(v) }
        ts_view_names = ts_views.map(&:name)
        # Skip records with matching names (includes the schema name
        # for records not in the public schema)
        pg_views.reject { |v| v.name.in?(ts_view_names) }
      end

      private

      def views_from_timescale
        connection.execute(<<-SQL.squish)
          SELECT
            view_name as viewname,
            view_definition AS definition,
            'm' AS kind,
            view_schema AS namespace
          FROM timescaledb_information.continuous_aggregates
        SQL
      end
    end

    class Adapter < ::Scenic::Adapters::Postgres
      # Timescale does some funky stuff under the hood with continuous
      # aggregates. A continuous aggregate is made up of:
      #
      # 1. A hypertable to store the materialized data
      # 2. An entry in the jobs table to refresh the data
      # 3. A view definition that union's the hypertable and any recent data
      #    not included in the hypertable
      #
      # That doesn't dump well, even to structure.sql (we lose the job
      # definition, since it's not part of the DDL).
      #
      # Our schema dumper implementation will handle dumping the continuous
      # aggregate definitions, but we need to override Scenic's schema dumping
      # to exclude those continuous aggregates.
      def views
        Views.new(connection).all
      end
    end
  end
end
