require 'spec_helper'

# Specs for the timezone_aware: true option on continuous_aggregates.
#
# The feature lets callers query UTC-stored cagg data in any IANA timezone without
# creating additional caggs via the in_timezone(tz) scope, which rebuckets rows by
# (time_column AT TIME ZONE tz)::date.  Use the finest-granularity cagg for correct
# day boundaries.
#
# Why not the daily cagg?
#   The daily cagg buckets by UTC midnight.  A local "day" in EST (UTC-5) starts at
#   05:00 UTC, so a UTC daily bucket always straddles two local calendar days.  Reading
#   from a sub-daily cagg and rebucketing avoids this.
#
# Why 30-minute granularity?
#   Most UTC offsets are whole hours, but IST (+5:30), ACST (+9:30), IRT (+3:30) and
#   NST (-3:30) use X:30 offsets.  A 30-min cagg covers all of them with a single level.

RSpec.describe 'timezone_aware continuous_aggregates' do
  let(:test_class) { HypertableWithTimezoneAwareCaggs }

  before(:all) do
    ActiveRecord::Base.connection.instance_exec do
      # Drop leftovers from any previous failed run
      HypertableWithTimezoneAwareCaggs.drop_continuous_aggregates rescue nil
      drop_table :hypertable_with_timezone_aware_caggs, if_exists: true, force: :cascade

      create_table(:hypertable_with_timezone_aware_caggs, id: false, hypertable: {
        time_column: 'ts', chunk_time_interval: '1 day'
      }) do |t|
        t.timestamptz :ts,              null: false
        t.bigint      :organization_id, null: false, default: 1
        t.float       :value,           null: false, default: 0.0
      end
    end

    HypertableWithTimezoneAwareCaggs.create_continuous_aggregates(with_data: false)
  end

  after(:all) do
    HypertableWithTimezoneAwareCaggs.drop_continuous_aggregates
    ActiveRecord::Base.connection.drop_table(
      :hypertable_with_timezone_aware_caggs, if_exists: true, force: :cascade
    )
  end

  # ── Class generation ──────────────────────────────────────────────────────

  describe 'class generation' do
    it 'creates a class for each timeframe' do
      expect(test_class.const_defined?(:MetricsPerHalfhour)).to be true
      expect(test_class.const_defined?(:MetricsPerDay)).to be true
    end

    it 'assigns correct table names' do
      expect(test_class::MetricsPerHalfhour.table_name).to eq('metrics_per_halfhour')
      expect(test_class::MetricsPerDay.table_name).to eq('metrics_per_day')
    end

    it 'uses the custom interval string for the halfhour timeframe' do
      expect(test_class::MetricsPerHalfhour.interval).to eq("'30 minutes'")
    end

    it 'uses the default 1-day interval for the day timeframe' do
      expect(test_class::MetricsPerDay.interval).to eq("'1 day'")
    end
  end

  # ── Base query / rollup correctness ──────────────────────────────────────

  describe 'base_query' do
    it 'halfhour cagg reads from the raw hypertable with a 30-minute bucket' do
      sql = test_class::MetricsPerHalfhour.base_query
      expect(sql).to include("time_bucket('30 minutes', ts)")
      expect(sql).to include('"hypertable_with_timezone_aware_caggs"')
    end

    it 'day cagg reads from the halfhour cagg, not the raw hypertable' do
      sql = test_class::MetricsPerDay.base_query
      expect(sql).to include("time_bucket('1 day', ts)")
      expect(sql).to include('"metrics_per_halfhour"')
      expect(sql).not_to include('"hypertable_with_timezone_aware_caggs"')
    end

    it 'day cagg rolls up SUM(total) and SUM(row_count) from the halfhour cagg' do
      sql = test_class::MetricsPerDay.base_query
      expect(sql).to match(/sum\(total\)/i)
      expect(sql).to match(/sum\(row_count\)/i)
    end
  end

  # ── in_timezone scope ─────────────────────────────────────────────────────

  describe '#in_timezone scope' do
    it 'is injected into every generated cagg class' do
      expect(test_class::MetricsPerHalfhour).to respond_to(:in_timezone)
      expect(test_class::MetricsPerDay).to     respond_to(:in_timezone)
    end

    it 'generates AT TIME ZONE SQL for the given timezone' do
      sql = test_class::MetricsPerHalfhour.in_timezone('America/New_York').to_sql
      expect(sql).to include("AT TIME ZONE 'America/New_York'")
    end

    it 'casts the result to a local date column named local_date' do
      sql = test_class::MetricsPerHalfhour.in_timezone('America/New_York').to_sql
      expect(sql).to include('::date AS local_date')
    end

    it 'includes a timezone literal column so consumers know which TZ the rows are in' do
      sql = test_class::MetricsPerHalfhour.in_timezone('America/New_York').to_sql
      expect(sql).to include("'America/New_York' AS timezone")
    end

    it 'reads from the cagg table, not the raw hypertable' do
      sql = test_class::MetricsPerHalfhour.in_timezone('Asia/Kolkata').to_sql
      expect(sql).to     include('"metrics_per_halfhour"')
      expect(sql).not_to include('"hypertable_with_timezone_aware_caggs"')
    end

    it 'does not contain a time_bucket call (rebuckets by local date instead)' do
      sql = test_class::MetricsPerHalfhour.in_timezone('Asia/Manila').to_sql
      expect(sql).not_to include('time_bucket')
    end

    it 'wraps each aggregate column in SUM()' do
      sql = test_class::MetricsPerHalfhour.in_timezone('UTC').to_sql
      expect(sql).to include('SUM(total)')
      expect(sql).to include('SUM(row_count)')
    end

    it 'groups by the local date expression and dimension columns' do
      sql = test_class::MetricsPerHalfhour.in_timezone('America/New_York').to_sql
      expect(sql).to match(/GROUP BY.*AT TIME ZONE.*organization_id/m)
    end

    it 'orders by the local date expression' do
      sql = test_class::MetricsPerHalfhour.in_timezone('America/New_York').to_sql
      expect(sql).to match(/ORDER BY.*AT TIME ZONE/m)
    end

    it 'is chainable with .where to pre-filter before aggregation' do
      sql = test_class::MetricsPerHalfhour
        .in_timezone('Asia/Kolkata')
        .where(organization_id: 42)
        .to_sql
      expect(sql).to include("'Asia/Kolkata'")
      expect(sql).to include('organization_id')
      # The WHERE is applied to the outer query wrapping the rebucketing subquery
      expect(sql).to include('WHERE')
      expect(sql).to match(/organization_id.*=.*42/m)
    end

    it 'works for a half-hour offset timezone (IST = UTC+5:30)' do
      sql = test_class::MetricsPerHalfhour.in_timezone('Asia/Kolkata').to_sql
      expect(sql).to include("'Asia/Kolkata'")
      expect(sql).to include('AT TIME ZONE')
    end
  end

  # ── Data correctness ──────────────────────────────────────────────────────
  #
  # We use January 2024 so America/New_York is EST (UTC-5, before DST on March 10).
  # Four rows straddle the UTC/EST day boundary:
  #
  #   2024-01-15 22:00 UTC  org=1  value=100  → EST 17:00 → local date 2024-01-15
  #   2024-01-15 23:00 UTC  org=1  value=200  → EST 18:00 → local date 2024-01-15
  #   2024-01-16 03:00 UTC  org=2  value=150  → EST 22:00 → local date 2024-01-15  ← crosses!
  #   2024-01-16 09:00 UTC  org=2  value=250  → EST 04:00 → local date 2024-01-16
  #
  # UTC daily cagg (wrong day boundaries for EST):
  #   2024-01-15: org=1 → 300
  #   2024-01-16: org=2 → 400   (both org=2 rows grouped on the 16th in UTC)
  #
  # in_timezone scope (correct local-day totals):
  #   2024-01-15: org=1 → 300,  org=2 → 150
  #   2024-01-16: org=2 → 250

  describe 'data correctness', :database_cleaner_strategy => :truncation do
    before(:all) do
      HypertableWithTimezoneAwareCaggs.insert_all([
        { ts: '2024-01-15 22:00:00+00', organization_id: 1, value: 100.0 },
        { ts: '2024-01-15 23:00:00+00', organization_id: 1, value: 200.0 },
        { ts: '2024-01-16 03:00:00+00', organization_id: 2, value: 150.0 },
        { ts: '2024-01-16 09:00:00+00', organization_id: 2, value: 250.0 },
      ])
      HypertableWithTimezoneAwareCaggs.refresh_aggregates
    end

    after(:all) do
      ActiveRecord::Base.connection.execute('TRUNCATE hypertable_with_timezone_aware_caggs')
    end

    let(:conn) { ActiveRecord::Base.connection }

    it 'total value is conserved: cagg sum equals raw sum' do
      raw_total  = HypertableWithTimezoneAwareCaggs.sum(:value)
      cagg_total = HypertableWithTimezoneAwareCaggs::MetricsPerHalfhour.sum(:total)
      expect(cagg_total).to eq(raw_total)
    end

    it 'in_timezone total equals the cagg total (value is conserved across TZ rebucketing)' do
      cagg_total = HypertableWithTimezoneAwareCaggs::MetricsPerHalfhour.sum(:total)
      tz_total   = HypertableWithTimezoneAwareCaggs::MetricsPerHalfhour
        .in_timezone('America/New_York')
        .map { |r| r['total'].to_f }
        .sum
      expect(tz_total).to eq(cagg_total)
    end

    it 'UTC daily cagg groups both org=2 rows on 2024-01-16 (wrong for EST)' do
      utc_jan16 = conn.select_value(<<~SQL).to_f
        SELECT SUM(total) FROM metrics_per_day
        WHERE organization_id = 2
          AND ts >= '2024-01-16'::timestamptz
          AND ts <  '2024-01-17'::timestamptz
      SQL
      expect(utc_jan16).to eq(400.0)
    end

    it 'in_timezone places the 03:00 UTC row on 2024-01-15 (= 22:00 EST the previous evening)' do
      ny_jan15 = HypertableWithTimezoneAwareCaggs::MetricsPerHalfhour
        .in_timezone('America/New_York')
        .where(organization_id: 2)
        .where("local_date = '2024-01-15'")
        .map { |r| r['total'].to_f }
        .sum
      expect(ny_jan15).to eq(150.0)
    end

    it 'in_timezone places the 09:00 UTC row on 2024-01-16 (= 04:00 EST)' do
      ny_jan16 = HypertableWithTimezoneAwareCaggs::MetricsPerHalfhour
        .in_timezone('America/New_York')
        .where(organization_id: 2)
        .where("local_date = '2024-01-16'")
        .map { |r| r['total'].to_f }
        .sum
      expect(ny_jan16).to eq(250.0)
    end
  end
end
