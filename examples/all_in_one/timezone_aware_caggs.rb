require 'bundler/inline'

gemfile(true) do
  gem 'timescaledb', path: '../..'
  gem 'pry'
end

require 'timescaledb'
require 'pp'

# ruby timezone_aware_caggs.rb postgres://user:pass@host:port/db_name
ActiveRecord::Base.establish_connection(ARGV.last)
ActiveRecord::Base.logger = nil

# ── Model ─────────────────────────────────────────────────────────────────────
#
# Data is always stored UTC in the hypertable.  Timezone-aware daily totals are
# produced on read via in_timezone(tz) — no extra caggs needed.
#
# The continuous_aggregates macro generates a 2-level hierarchy:
#
#   page_views (hypertable, UTC)
#     ├── page_view_stats_per_halfhour  (30-min cagg — source for TZ queries)
#     └── page_view_stats_per_day      (UTC daily rollup)
#
# timezone_aware: true injects in_timezone(tz) into every generated cagg class.

class PageView < ActiveRecord::Base
  self.primary_key = nil

  extend  Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts'

  scope :page_view_stats, -> {
    select(
      "user_id, app_id",
      "count(*) as views",
      "sum(duration) as total_duration"
    ).group("user_id, app_id")
  }

  continuous_aggregates(
    scopes:     [:page_view_stats],
    timeframes: [:halfhour, :day],

    # Map :halfhour to the SQL interval '30 minutes'.
    # Covers whole-hour AND X:30 UTC offsets: IST +5:30, ACST +9:30, IRT +3:30, NST -3:30.
    timeframe_intervals: { halfhour: '30 minutes' },

    # Inject in_timezone into every generated cagg class.
    timezone_aware: true,

    refresh_policy: {
      halfhour: { start_offset: '3 hours', end_offset: '30 minutes', schedule_interval: '30 minutes' },
      day:      { start_offset: '3 days',  end_offset: '1 hour',     schedule_interval: '1 hour'     }
    }
  )
end

# ── Schema ────────────────────────────────────────────────────────────────────

conn = ActiveRecord::Base.connection
conn.instance_exec do
  PageView.drop_continuous_aggregates rescue nil
  drop_table :page_views, if_exists: true, force: :cascade

  create_table(:page_views, id: false, hypertable: {
    time_column: 'ts', chunk_time_interval: '7 days'
  }) do |t|
    t.timestamptz :ts,       null: false
    t.bigint      :user_id,  null: false
    t.bigint      :app_id,   null: false
    t.integer     :duration, null: false, default: 0
  end
end
puts "Created page_views hypertable"

PageView.create_continuous_aggregates(with_data: false)
puts "Created caggs:"
puts "  page_view_stats_per_halfhour  (30-min UTC buckets)"
puts "  page_view_stats_per_day       (daily UTC rollup)"

# ── Seed data ─────────────────────────────────────────────────────────────────
#
# Insert rows that straddle the UTC midnight boundary so the day-shift effect
# is clearly visible in the output below.
#
# 2024-01-15 22:00 UTC  user=1  → EST 17:00 → local date 2024-01-15
# 2024-01-15 23:00 UTC  user=1  → EST 18:00 → local date 2024-01-15
# 2024-01-16 03:00 UTC  user=2  → EST 22:00 → local date 2024-01-15  ← crosses midnight!
# 2024-01-16 09:00 UTC  user=2  → EST 04:00 → local date 2024-01-16

PageView.insert_all([
  { ts: '2024-01-15 22:00:00+00', user_id: 1, app_id: 1, duration: 3600 },
  { ts: '2024-01-15 23:00:00+00', user_id: 1, app_id: 1, duration: 1800 },
  { ts: '2024-01-16 03:00:00+00', user_id: 2, app_id: 1, duration: 2700 },
  { ts: '2024-01-16 09:00:00+00', user_id: 2, app_id: 1, duration:  900 },
])
PageView.refresh_aggregates
puts "\nSeeded 4 rows and refreshed caggs"

# ── Query examples ────────────────────────────────────────────────────────────

puts "\n── UTC daily cagg (wrong day boundaries for non-UTC timezones) ────────"
PageView::PageViewStatsPerDay.order(:ts).each do |r|
  puts "  #{r.ts.to_date}  user=#{r.user_id}  duration=#{r.total_duration}s"
end

puts "\n── in_timezone scope (ad-hoc, any timezone) ──────────────────────────"
puts "  America/New_York (EST = UTC-5):"
PageView::PageViewStatsPerHalfhour.in_timezone('America/New_York').each do |r|
  puts "  local_date=#{r['local_date']}  user=#{r['user_id']}  duration=#{r['total_duration']}s"
end

puts "\n  Asia/Kolkata (IST = UTC+5:30, half-hour offset):"
PageView::PageViewStatsPerHalfhour.in_timezone('Asia/Kolkata').each do |r|
  puts "  local_date=#{r['local_date']}  user=#{r['user_id']}  duration=#{r['total_duration']}s"
end

puts "\n── Composing scope with WHERE ─────────────────────────────────────────"
puts "  Only user=2, Asia/Manila:"
PageView::PageViewStatsPerHalfhour
  .in_timezone('Asia/Manila')
  .where(user_id: 2)
  .each do |r|
    puts "  local_date=#{r['local_date']}  duration=#{r['total_duration']}s"
  end

puts "\n── Day-boundary proof ────────────────────────────────────────────────"
utc_jan16_u2 = PageView::PageViewStatsPerDay
  .where(user_id: 2)
  .where(ts: '2024-01-16'..'2024-01-17')
  .sum(:total_duration).to_i

ny_jan15_u2 = PageView::PageViewStatsPerHalfhour
  .in_timezone('America/New_York')
  .where(user_id: 2)
  .where("local_date = '2024-01-15'")
  .map { |r| r['total_duration'].to_i }.sum

ny_jan16_u2 = PageView::PageViewStatsPerHalfhour
  .in_timezone('America/New_York')
  .where(user_id: 2)
  .where("local_date = '2024-01-16'")
  .map { |r| r['total_duration'].to_i }.sum

puts "  user=2's 03:00 UTC row (= 22:00 EST on the 15th):"
puts "    UTC daily cagg says 2024-01-16 → #{utc_jan16_u2}s total (merges both rows)"
puts "    in_timezone says 2024-01-15 → #{ny_jan15_u2}s  (correctly shifted to prev evening)"
puts "    in_timezone says 2024-01-16 → #{ny_jan16_u2}s  (only the 09:00 UTC row)"

# ── Clean up ──────────────────────────────────────────────────────────────────

PageView.drop_continuous_aggregates
puts "\nDropped caggs.  Done."

binding.pry
