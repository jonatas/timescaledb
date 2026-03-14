module Timescaledb
  module ContinuousAggregatesHelper
    extend ActiveSupport::Concern

    included do
      class_attribute :rollup_rules, default: {
        /count\(\*\)\s+as\s+(\w+)/ => 'sum(\1) as \1',
        /sum\((\w+)\)\s+as\s+(\w+)/ => 'sum(\2) as \2',
        /min\((\w+)\)\s+as\s+(\w+)/ => 'min(\2) as \2',
        /max\((\w+)\)\s+as\s+(\w+)/ => 'max(\2) as \2',
        /first\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'first(\3, \2) as \3',
        /high\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'max(\1) as \1',
        /low\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'min(\1) as \1',
        /last\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'last(\3, \2) as \3',
        /candlestick_agg\((\w+),\s*(\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'rollup(\4) as \4',
        /stats_agg\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'rollup(\3) as \3',
        /stats_agg\((\w+)\)\s+as\s+(\w+)/ => 'rollup(\2) as \2',
        /state_agg\((\w+)\)\s+as\s+(\w+)/ => 'rollup(\2) as \2',
        /percentile_agg\((\w+),\s*(\w+)\)\s+as\s+(\w+)/ => 'rollup(\3) as \3',
        /heartbeat_agg\((\w+)\)\s+as\s+(\w+)/ => 'rollup(\2) as \2',
        /stats_agg\(([^)]+)\)\s+(as\s+(\w+))/ => 'rollup(\3) \2',
        /stats_agg\((.*)\)\s+(as\s+(\w+))/ => 'rollup(\3) \2'
      }

      scope :rollup, ->(interval) do
        select_values = (self.select_values - ["time"]).select{|e|!e.downcase.start_with?("time_bucket")}
        if self.select_values.any?{|e|e.downcase.start_with?('time_bucket(')} || self.select_values.include?('time')
          select_values = apply_rollup_rules(select_values)
          select_values.gsub!(/time_bucket\((.+), (.+)\)/, "time_bucket(#{interval}, \2)")
          select_values.gsub!(/\btime\b/, "time_bucket(#{interval}, time) as time")
        end
        group_values = self.group_values.dup

        if self.segment_by_column
          if !group_values.include?(self.segment_by_column)
            group_values << self.segment_by_column
          end
          if !select_values.include?(self.segment_by_column.to_s)
            select_values.insert(0, self.segment_by_column.to_s)
          end
        end
        where_values = self.where_values_hash
        tb = "time_bucket(#{interval}, #{time_column})"
        self.unscoped.select("#{tb} as #{time_column}, #{select_values.join(', ')}")
          .where(where_values)
          .group(tb, *group_values)
      end
    end

    class_methods do
      def continuous_aggregates(options = {})
        @time_column = options[:time_column] || self.time_column
        @timeframes = options[:timeframes] || [:minute, :hour, :day, :week, :month, :year]
        @timezone_aware = options.fetch(:timezone_aware, false)
        # Custom interval strings for timeframe names that don't follow '1 <name>' convention.
        # Example: { halfhour: '30 minutes' } makes the 'halfhour' timeframe use INTERVAL '30 minutes'.
        @timeframe_intervals = options[:timeframe_intervals] || {}

        scopes = options[:scopes] || []
        @aggregates = {}

        scopes.each do |scope_name|
          @aggregates[scope_name] = {
            scope_name: scope_name,
            select: nil,
            group_by: nil,
            refresh_policy: options[:refresh_policy] || {}
          }
        end

        # Allow for custom aggregate definitions to override or add to scope-based ones
        @aggregates.merge!(options[:aggregates] || {})

        # Add custom rollup rules if provided
        self.rollup_rules.merge!(options[:custom_rollup_rules] || {})

        define_continuous_aggregate_classes unless options[:skip_definition]
      end

      def refresh_aggregates(timeframes = nil)
        timeframes ||= @timeframes
        @aggregates.each do |aggregate_name, _|
          timeframes.each do |timeframe|
            klass = const_get("#{aggregate_name}_per_#{timeframe}".classify)
            klass.refresh!
          end
        end
      end

      def create_continuous_aggregates(with_data: false)
        @aggregates.each do |aggregate_name, config|
          @timeframes.each do |timeframe|
            klass = const_get("#{aggregate_name}_per_#{timeframe}".classify)
            connection.execute <<~SQL
              CREATE MATERIALIZED VIEW IF NOT EXISTS #{klass.table_name}
              WITH (timescaledb.continuous) AS
              #{klass.base_query}
              #{with_data ? 'WITH DATA' : 'WITH NO DATA'};
            SQL

            if (policy = klass.refresh_policy)
              connection.execute <<~SQL
                SELECT add_continuous_aggregate_policy('#{klass.table_name}',
                  start_offset => INTERVAL '#{policy[:start_offset]}',
                  end_offset =>  INTERVAL '#{policy[:end_offset]}',
                  schedule_interval => INTERVAL '#{policy[:schedule_interval]}');
              SQL
            end
          end
        end
      end

      def apply_rollup_rules(select_values)
        result = select_values.dup
        rollup_rules.each do |pattern, replacement|
          result.gsub!(pattern, replacement)
        end
        # Remove any remaining time_bucket
        result.gsub!(/time_bucket\(.+?\)( as \w+)?/, '')
        result
      end

      def drop_continuous_aggregates
        @aggregates.each do |aggregate_name, _|
          @timeframes.reverse_each do |timeframe|
            view_name = "#{aggregate_name}_per_#{timeframe}"
            connection.execute("DROP MATERIALIZED VIEW IF EXISTS #{view_name} CASCADE")
          end
        end
      end

      private

      # Builds the SQL interval string for a timeframe.
      # Uses @timeframe_intervals for custom mappings (e.g. halfhour => '30 minutes'),
      # otherwise falls back to '1 <timeframe>' (e.g. hour => '1 hour').
      def interval_for(timeframe)
        custom = @timeframe_intervals[timeframe]
        custom ? "'#{custom}'" : "'1 #{timeframe}'"
      end

      # Extracts the aggregated column aliases from the cagg's select clause.
      # Returns only the aliases that are NOT plain dimension columns (i.e. not
      # in group_by), so we know which columns to wrap in SUM() for TZ rebucketing.
      def tz_aggregate_aliases(config)
        dims = Array(config[:group_by]).map(&:to_s)
        config[:select].to_s
          .scan(/\bas\s+(\w+)/i)
          .flatten
          .reject { |a| dims.include?(a) }
      end

      def define_continuous_aggregate_classes
        base_model      = self
        tz_aware        = @timezone_aware

        @aggregates.each do |aggregate_name, config|
          previous_timeframe = nil
          @timeframes.each do |timeframe|
            _table_name = "#{aggregate_name}_per_#{timeframe}"
            class_name  = "#{aggregate_name}_per_#{timeframe}".classify

            const_set(class_name, Class.new(base_model) do
              class << self
                attr_accessor :config, :timeframe, :base_query, :base_model,
                              :previous_timeframe, :interval, :aggregate_name, :prev_klass
              end

              self.table_name        = _table_name
              self.config            = config
              self.timeframe         = timeframe
              self.previous_timeframe = previous_timeframe
              self.aggregate_name    = aggregate_name
              self.interval          = base_model.send(:interval_for, timeframe)
              self.base_model        = base_model

              def self.prev_klass
                base_model.const_get("#{aggregate_name}_per_#{previous_timeframe}".classify)
              end

              def self.base_query
                @base_query ||= begin
                  tb = "time_bucket(#{interval}, #{time_column})"
                  if previous_timeframe
                    select_clause = base_model.apply_rollup_rules("#{config[:select]}")
                    # Note there's no where clause here, because we're using the previous timeframe's data
                    "SELECT #{tb} as #{time_column}, #{select_clause} FROM \"#{prev_klass.table_name}\" GROUP BY #{[tb, *config[:group_by]].join(', ')}"
                  else
                    scope = base_model.public_send(config[:scope_name])
                    config[:select]   = scope.select_values.select{|e|!e.downcase.start_with?("time_bucket")}.join(', ')
                    config[:group_by] = scope.group_values
                    config[:where] =
                      if scope.where_values_hash.present?
                        scope.where_values_hash.map { |key, value| "#{key} = '#{value}'" }.join(' AND ')
                      elsif scope.where_clause.ast.present? && scope.where_clause.ast.to_sql.present?
                        scope.where_clause.ast.to_sql
                      end

                    sql  = "SELECT #{tb} as #{time_column}, #{config[:select]}"
                    sql += " FROM \"#{base_model.table_name}\""
                    sql += " WHERE #{config[:where]}" if config[:where]
                    sql += " GROUP BY #{[tb, *config[:group_by]].join(', ')}"
                    sql
                  end
                end
              end

              def self.refresh!(start_time = nil, end_time = nil)
                if start_time && end_time
                  connection.execute("CALL refresh_continuous_aggregate('#{table_name}', '#{start_time}', '#{end_time}')")
                else
                  connection.execute("CALL refresh_continuous_aggregate('#{table_name}', null, null)")
                end
              end

              def readonly?
                true
              end

              def self.refresh_policy
                config[:refresh_policy]&.dig(timeframe)
              end

              if tz_aware
                # Capture the generated class name and base model so the scope lambda
                # can resolve them at call time. Rails evaluates scope lambdas with
                # `self` bound to the AR relation, not the class, so we need explicit
                # closure references to reach base_query and connection.
                _class_name = class_name
                _base_model = base_model

                # Returns a relation that rebuckets this cagg's pre-aggregated rows
                # into local calendar days for the given IANA timezone.
                #
                # Use the finest-granularity cagg (e.g. 30-min) for correct day
                # boundaries: the daily cagg buckets by UTC midnight, which straddles
                # local calendar days for any non-UTC zone.
                #
                # Benchmarking showed this subquery scope outperforms a permanent SQL
                # VIEW because the time_column predicate stays in the inner query where
                # the planner can apply chunk exclusion.
                scope :in_timezone, ->(tz) {
                  generated_klass = _base_model.const_get(_class_name)
                  generated_klass.base_query unless config[:group_by]

                  conn     = _base_model.connection
                  tz_safe  = conn.quote(tz)
                  tz_date  = "(%s AT TIME ZONE %s)::date" % [_base_model.time_column, tz_safe]
                  dims_sql = config[:group_by].join(', ')
                  agg_sql  = _base_model.send(:tz_aggregate_aliases, config)
                             .map { |a| "SUM(#{a}) AS #{a}" }
                             .join(', ')

                  # Wrap in a derived table so chained .where(local_date: ...) works —
                  # PostgreSQL forbids referencing SELECT aliases in the same query's
                  # WHERE, but they become real columns once exposed through a subquery.
                  inner_sql = <<~SQL.squish
                    SELECT #{tz_date} AS local_date,
                           #{tz_safe} AS timezone,
                           #{dims_sql},
                           #{agg_sql}
                    FROM "#{table_name}"
                    GROUP BY #{tz_date}, #{dims_sql}
                    ORDER BY #{tz_date}
                  SQL

                  unscoped
                    .select(Arel.sql('*'))
                    .from(Arel.sql("(#{inner_sql}) AS #{table_name}"))
                }
              end
            end)

            previous_timeframe = timeframe
          end
        end
      end
    end
  end
end
