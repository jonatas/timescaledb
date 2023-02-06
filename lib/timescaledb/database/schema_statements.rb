module Timescaledb
  class Database
    module SchemaStatements
      # @see https://docs.timescale.com/api/latest/hypertable/create_hypertable/#create_hypertable
      #
      # @param [String] relation The identifier of the table to convert to hypertable
      # @param [String] time_column_name The name of the column containing time values as well as the primary column to partition by
      # @param [Hash] options The optional arguments
      # @return [String] The create_hypertable SQL statement
      def create_hypertable_sql(relation, time_column_name, **options)
        options.transform_keys!(&:to_sym)

        partitioning_column = options.delete(:partitioning_column)
        number_partitions = options.delete(:number_partitions)

        arguments  = [quote(relation), quote(time_column_name)]
        arguments += [quote(partitioning_column), number_partitions] if partitioning_column && number_partitions
        arguments += cast_create_hypertable_optional_arguments(options)

        "SELECT create_hypertable(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/compression/alter_table_compression/#alter-table-compression
      #
      # @param [String] hypertable The name of the hypertable to enable compression
      # @param [Hash] options The optional arguments
      # @return [String] The ALTER TABLE SQL to enable compression
      def enable_hypertable_compression_sql(hypertable, **options)
        options.transform_keys!(&:to_sym)

        compress_orderby = options.delete(:compress_orderby)
        compress_segmentby = options.delete(:compress_segmentby)

        arguments = ['timescaledb.compress']
        arguments << "timescaledb.compress_orderby = #{quote(compress_orderby)}" if compress_orderby
        arguments << "timescaledb.compress_segmentby = #{quote(compress_segmentby)}" if compress_segmentby

        "ALTER TABLE #{hypertable} SET (#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/compression/alter_table_compression/#alter-table-compression
      #
      # @param [String] hypertable The name of the hypertable to disable compression
      # @return [String] The ALTER TABLE SQL to disable compression
      def disable_hypertable_compression_sql(hypertable)
        "ALTER TABLE #{hypertable} SET (timescaledb.compress = FALSE);"
      end

      # @see https://docs.timescale.com/api/latest/compression/add_compression_policy/#add_compression_policy
      #
      # @param [String] hypertable The name of the hypertable or continuous aggregate to create the policy for
      # @param [String] compress_after The age after which the policy job compresses chunks
      # @param [Hash] options The optional arguments
      # @return [String] The add_compression_policy SQL statement
      def add_compression_policy_sql(hypertable, compress_after, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable), interval_to_sql(compress_after)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT add_compression_policy(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/compression/remove_compression_policy/#remove_compression_policy
      #
      # @param [String] hypertable The name of the hypertable to remove the policy from
      # @param [Hash] options The optional arguments
      # @return [String] The remove_compression_policy SQL statement
      def remove_compression_policy_sql(hypertable, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT remove_compression_policy(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/data-retention/add_retention_policy/#add_retention_policy
      #
      # @param [String] hypertable The name of the hypertable to create the policy for
      # @param [String] drop_after The age after which the policy job drops chunks
      # @param [Hash] options The optional arguments
      # @return [String] The add_retention_policy SQL statement
      def add_retention_policy_sql(hypertable, drop_after, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable), interval_to_sql(drop_after)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT add_retention_policy(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/data-retention/remove_retention_policy/#remove_retention_policy
      #
      # @param [String] hypertable The name of the hypertable to remove the policy from
      # @param [Hash] options The optional arguments
      # @return [String] The remove_retention_policy SQL statement
      def remove_retention_policy_sql(hypertable, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT remove_retention_policy(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/hypertable/add_reorder_policy/#add_reorder_policy
      #
      # @param [String] hypertable The name of the hypertable to create the policy for
      # @param [String] index_name The existing index by which to order rows on disk
      # @param [Hash] options The optional arguments
      # @return [String] The add_reorder_policy SQL statement
      def add_reorder_policy_sql(hypertable, index_name, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable), quote(index_name)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT add_reorder_policy(#{arguments.join(', ')});"
      end

      # @see https://docs.timescale.com/api/latest/hypertable/remove_reorder_policy/#remove_reorder_policy
      #
      # @param [String] hypertable The name of the hypertable to remove the policy from
      # @param [Hash] options The optional arguments
      # @return [String] The remove_retention_policy SQL statement
      def remove_reorder_policy_sql(hypertable, **options)
        options.transform_keys!(&:to_sym)

        arguments = [quote(hypertable)]
        arguments += cast_policy_optional_arguments(options)

        "SELECT remove_reorder_policy(#{arguments.join(', ')});"
      end

      private

      # @param [Array<Hash<Symbol, Object>>] options The policy optional arguments.
      # @return [Array<String>]
      def cast_policy_optional_arguments(options)
        options.map do |option, value|
          case option
          when :if_not_exists, :if_exists then "#{option} => #{boolean_to_sql(value)}"
          when :initial_start, :timezone then "#{option} => #{quote(value)}"
          end
        end.compact
      end

      # @param [Array<Hash<Symbol, Object>>] options The create_hypertable optional arguments.
      # @return [Array<String>]
      def cast_create_hypertable_optional_arguments(options)
        options.map do |option, value|
          case option
          when :chunk_time_interval
            "#{option} => #{interval_to_sql(value)}"
          when :if_not_exists, :create_default_indexes, :migrate_data, :distributed
            "#{option} => #{boolean_to_sql(value)}"
          when :partitioning_func, :associated_schema_name,
               :associated_table_prefix, :time_partitioning_func
            "#{option} => #{quote(value)}"
          when :replication_factor
            "#{option} => #{value}"
          end
        end.compact
      end
    end
  end
end
