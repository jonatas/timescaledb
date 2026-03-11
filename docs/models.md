# Models

The ActiveRecord is the default ORM in the Ruby community. We have introduced a macro that helps you to inject the behavior as other libraries do in the Rails ecosystem.

You need to extend the Timescaledb::ActsAsHypertable module in your model. Ideally, you should include the Timescaledb::ContinuousAggregates module and also separate the definition of the continuous aggregate from the model.

```ruby
class Hypertable < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregates

  def abstract_class
    true
  end
end
```

## The `acts_as_hypertable` macro

You can declare a Rails model as a Hypertable by invoking the `acts_as_hypertable` macro. This macro extends your existing model with timescaledb-related functionality. Here's the macro using the default options, you can pass the following options:

- `time_column`: The name of the column that will be used as the time column.
- `chunk_time_interval`: The interval at which chunks will be created.

```ruby
class Event < Hypertable
  acts_as_hypertable time_column: :created_at, chunk_time_interval: '1 day'
end
```

## The `continuous_aggregates` macro

You can declare continuous aggregates for a Rails model by invoking the `continuous_aggregates` macro. This macro extends your existing model with TimescaleDB-related functionality for efficient data aggregation and querying.

```ruby 
# Example from RubyGems server
class Download < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts'

  scope :total_downloads, -> { select("count(*) as total") }
  scope :downloads_by_gem, -> { select("gem_name, count(*) as total").group(:gem_name) }
  scope :downloads_by_version, -> { select("gem_name, gem_version, count(*) as total").group(:gem_name, :gem_version) }

  continuous_aggregates(
    timeframes: [:minute, :hour, :day, :month],
    scopes: [:total_downloads, :downloads_by_gem, :downloads_by_version],
    refresh_policy: {
      minute: { start_offset: "10 minutes", end_offset: "1 minute", schedule_interval: "1 minute" },
      hour:   { start_offset: "4 hour",     end_offset: "1 hour",   schedule_interval: "1 hour" },
      day:    { start_offset: "3 day",      end_offset: "1 day",    schedule_interval: "1 day" },
      month:  { start_offset: "3 month",    end_offset: "1 day",  schedule_interval: "1 day" }
  })
end
```

#### The `create_continuous_aggregates` method and `drop_continuous_aggregates` methods for migrations

The macro will create a continuous aggregate for each timeframe and scope you specify.
After defining the continuous aggregate, you can use the `create_continuous_aggregate` method to create the continuous aggregate in the database.

```ruby
class SetupMyAmazingCaggsMigration < ActiveRecord::Migration[7.0]
  def up
    Download.create_continuous_aggregates
  end

  def down
    Download.drop_continuous_aggregates
  end
end
```

It will automatically rollup all materialized views for all timeframes and scopes.


## How rollup works

The most important part of using multiple timeframes and scopes is to understand how the rollup works.

The rollup is a process that will create a new row for each timeframe and scope.

For example, if you have a scope called `total_downloads` and a timeframe of `day`, the rollup will rewrite the query to group by the day.

```sql
# Original query
SELECT count(*) FROM downloads;

# Rolled up query
SELECT time_bucket('1 day', created_at) AS day, count(*) FROM downloads GROUP BY day;
```

The rollup method will help to rollup such queries in a more efficient way.

```ruby
Download.total_downloads.map(&:attributes) #  => [{"total"=>6175}
# SELECT count(*) as total FROM "downloads"
```

Rollup to 1 minute:

```ruby
Download.total_downloads.rollup("'1 min'").map(&:attributes)
# SELECT time_bucket('1 min', ts) as ts, count(*) as total FROM "downloads" GROUP BY 1
=> [{"ts"=>2024-04-26 00:10:00 UTC, "total"=>110},
 {"ts"=>2024-04-26 00:11:00 UTC, "total"=>1322},
 {"ts"=>2024-04-26 00:12:00 UTC, "total"=>1461},
 {"ts"=>2024-04-26 00:13:00 UTC, "total"=>1150},
 {"ts"=>2024-04-26 00:14:00 UTC, "total"=>1127},
 {"ts"=>2024-04-26 00:15:00 UTC, "total"=>1005}]
```
 
### Aggregates classes

The `continuous_aggregates` macro will also create a class for each aggregate.

```ruby
Download::TotalDownloadsPerMinute.all.map(&:attributes)
# SELECT "total_downloads_per_minute".* FROM "total_downloads_per_minute"
=> [{"ts"=>2024-04-26 00:10:00 UTC, "total"=>110},
 {"ts"=>2024-04-26 00:11:00 UTC, "total"=>1322},
 {"ts"=>2024-04-26 00:12:00 UTC, "total"=>1461},
 {"ts"=>2024-04-26 00:13:00 UTC, "total"=>1150},
 {"ts"=>2024-04-26 00:14:00 UTC, "total"=>1127},
 {"ts"=>2024-04-26 00:15:00 UTC, "total"=>1005}]
```

The class also can rollup to other timeframes:

```ruby
Download::TotalDownloadsPerMinute.select("sum(total) as total").rollup("'2 min'").map(&:attributes)
# SELECT time_bucket('2 min', ts) as ts, sum(total) as total FROM "total_downloads_per_minute" GROUP BY 1
=> [{"ts"=>2024-04-26 00:12:00 UTC, "total"=>2611}, {"ts"=>2024-04-26 00:14:00 UTC, "total"=>2132}, {"ts"=>2024-04-26 00:10:00 UTC, "total"=>1432}]
```

You can also get the base query where continuous aggregate is created from:

```ruby
Download::TotalDownloadsPerMinute.base_query.to_sql
=> "SELECT time_bucket('1 minute', ts) as ts, count(*) as total FROM \"downloads\" GROUP BY 1"
```

In case of hierarchy of continuous aggregates, you can get the parent query:

```ruby
Download::TotalDownloadsPerMonth.parent_query.to_sql
=> "SELECT time_bucket('1 month', ts) as ts, sum(total) as total FROM \"total_downloads_per_day\" GROUP BY 1"
```

The config is the same as the one you pass to the `continuous_aggregates` macro. But it will be nested with the scope name.

```ruby
Download::DownloadsByGemPerMonth.config
=> {:scope_name=>:downloads_by_gem,
 :select=>"gem_name, count(*) as total",
 :group_by=>[:gem_name],
 :refresh_policy=>
  {:minute=>{:start_offset=>"10 minutes", :end_offset=>"1 minute", :schedule_interval=>"1 minute"},
   :hour=>{:start_offset=>"4 hour", :end_offset=>"1 hour", :schedule_interval=>"1 hour"},
   :day=>{:start_offset=>"3 day", :end_offset=>"1 day", :schedule_interval=>"1 day"},
   :month=>{:start_offset=>"3 month", :end_offset=>"1 day", :schedule_interval=>"1 day"}}}
```

## Timezone-aware continuous aggregates

TimescaleDB stores all data in UTC.  Most time-series applications need to
present that data in a user-selected or org-specific timezone — but naively
querying a UTC daily cagg in another timezone produces wrong results because
UTC midnight does not align with the local midnight of any non-UTC zone.

The `timezone_aware: true` option solves this by injecting the `in_timezone`
scope into every generated cagg class so callers can obtain correct
**local-day** totals without creating additional caggs.

### How it works

Instead of creating timezone-shifted caggs (which would require one cagg per
timezone), the gem generates SQL that reads from the finest-granularity cagg
(e.g. 30-minute or hourly) and rebuckets on read:

```sql
-- generated by PageView::PageViewStatsPerHalfhour.in_timezone('America/New_York')
SELECT (ts AT TIME ZONE 'America/New_York')::date AS local_date,
       'America/New_York' AS timezone,
       user_id, app_id,
       SUM(views) AS views,
       SUM(total_duration) AS total_duration
FROM "page_view_stats_per_halfhour"
GROUP BY (ts AT TIME ZONE 'America/New_York')::date,
         user_id, app_id
ORDER BY (ts AT TIME ZONE 'America/New_York')::date
```

No CASE WHEN flag evaluation, no raw-table scan — it reads the
already-aggregated 30-min integers and rebuckets them by local date.

### Why a sub-daily cagg as the source?

The daily cagg buckets by **UTC midnight**.  A "day" in EST (UTC-5) starts at
05:00 UTC, so a UTC daily bucket always straddles two local calendar days.
Reading from the 30-minute (or hourly) cagg and rebucketing by
`(ts AT TIME ZONE tz)::date` gives the correct answer for every timezone.

### Why 30-minute granularity?

Most UTC offsets are whole hours, but several major regions use X:30 offsets:

| Timezone        | Offset  | Region                    |
|-----------------|---------|---------------------------|
| Asia/Kolkata    | +05:30  | India (1.4 B people)      |
| Australia/Darwin| +09:30  | Central Australia         |
| Asia/Tehran     | +03:30  | Iran                      |
| America/St_Johns| −03:30  | Newfoundland, Canada      |

A 30-min cagg covers all of these.  Use `timeframe_intervals:` to map a
symbolic name to the actual SQL interval:

```ruby
continuous_aggregates(
  timeframes:          [:halfhour, :day],
  timeframe_intervals: { halfhour: '30 minutes' },
  timezone_aware:      true,
  ...
)
```

### Full example

```ruby
class PageView < ActiveRecord::Base
  extend  Timescaledb::ActsAsHypertable
  include Timescaledb::ContinuousAggregatesHelper

  acts_as_hypertable time_column: 'ts'

  scope :page_view_stats, -> {
    select("user_id, app_id, count(*) as views, sum(duration) as total_duration")
      .group("user_id, app_id")
  }

  continuous_aggregates(
    scopes:              [:page_view_stats],
    timeframes:          [:halfhour, :day],
    timeframe_intervals: { halfhour: '30 minutes' },
    timezone_aware:      true,
    refresh_policy: {
      halfhour: { start_offset: '3 hours', end_offset: '30 minutes', schedule_interval: '30 minutes' },
      day:      { start_offset: '3 days',  end_offset: '1 hour',     schedule_interval: '1 hour'     }
    }
  )
end
```

This generates two classes — `PageViewStatsPerHalfhour`, `PageViewStatsPerDay`
— each of which gains the `in_timezone` scope.

### `in_timezone(tz)` — scope

Returns an ActiveRecord relation rebucketed to local calendar days.  Works
with any IANA timezone at query time.

```ruby
# Daily totals for app=5 in Eastern Time
PageView::PageViewStatsPerHalfhour
  .in_timezone('America/New_York')
  .where(app_id: 5)
  .where("local_date BETWEEN '2024-01-01' AND '2024-01-31'")
  .each { |r| puts "#{r['local_date']}  #{r['views']} views" }

# Works for half-hour offsets too (IST = UTC+5:30)
PageView::PageViewStatsPerHalfhour
  .in_timezone('Asia/Kolkata')
  .where(app_id: 5)
  .map { |r| [r['local_date'], r['views']] }
```

!!! tip
    For large date ranges, also filter on the raw time column (`ts`) in the
    inner query — the planner can use chunk exclusion on the UTC column but
    not on the computed `local_date` alias.

### Day-boundary proof

```
Row at 03:00 UTC on Jan 16 = 22:00 EST on Jan 15

UTC daily cagg    → groups with Jan 16 (wrong for EST users)
in_timezone scope → groups with Jan 15 (correct: it was still Monday evening)
```

```ruby
# Both user=2 rows appear on Jan 16 in the UTC daily cagg
PageView::PageViewStatsPerDay.where(
  user_id: 2, ts: '2024-01-16'..'2024-01-17'
).sum(:total_duration)
# => 3600  (03:00 UTC + 09:00 UTC rows together — wrong day boundary for EST)

# in_timezone correctly splits them across local days
PageView::PageViewStatsPerHalfhour
  .in_timezone('America/New_York')
  .where(user_id: 2, local_date: '2024-01-15')
  .sum('total_duration')
# => 2700  (03:00 UTC = 22:00 EST on the 15th)

PageView::PageViewStatsPerHalfhour
  .in_timezone('America/New_York')
  .where(user_id: 2, local_date: '2024-01-16')
  .sum('total_duration')
# => 900   (09:00 UTC = 04:00 EST on the 16th)
```

## Metadata from the hypertable

When you use the `acts_as_hypertable` macro, it will define several methods to help you to inspect timescaledb metadata like chunks and hypertable metadata.

### Chunks

To get all the chunks from a model's hypertable, you can use `.chunks`.

```ruby
Event.chunks # => [#<Timescaledb::Chunk>, ...]
```

!!! warning
    The `chunks` method is only available when you use the `acts_as_hypertable` macro.
    By default, the macro will define several scopes and class methods to help you
    to inspect timescaledb metadata like chunks and hypertable metadata.
    You can disable this behavior by passing `skip_association_scopes`:
    ```ruby
    class Event < ActiveRecord::Base
      acts_as_hypertable skip_association_scopes: true
    end
    Event.chunks # => NoMethodError
    ```

### Hypertable metadata

To get the models' hypertable metadata, you can use `.hypertable`.

```ruby
Event.hypertable # => #<Timescaledb::Hypertable>
```

To get hypertable metadata for all hypertables: `Timescaledb.hypertables`.

### Compression Settings

Compression settings are accessible through the hypertable.

```ruby
Event.hypertable.compression_settings # => [#<Timescaledb::CompressionSettings>, ...]
```

To get compression settings for all hypertables: `Timescaledb.compression_settings`.

### Scopes

When you enable ActsAsHypertable on your model, we include a few default scopes. They are:

| Scope name             | What they return                      |
|------------------------|---------------------------------------|
| `Model.previous_month` | Records created in the previous month |
| `Model.previous_week`  | Records created in the previous week  |
| `Model.this_month`     | Records created this month            |
| `Model.this_week`      | Records created this week             |
| `Model.yesterday`      | Records created yesterday             |
| `Model.today`          | Records created today                 |
| `Model.last_hour`      | Records created in the last hour      |

All time-related scopes respect your application's timezone.

!!! warning
    To disable these scopes, pass `skip_default_scopes: true` to the `acts_as_hypertable` macro.
    ```ruby
    class Event < ActiveRecord::Base
      acts_as_hypertable skip_default_scopes: true
    end
    ```

## Scenic integration

The [Scenic](https://github.com/scenic-views/scenic) gem is easy to
manage database view definitions for a Rails application. Unfortunately, TimescaleDB's continuous aggregates are more complex than regular PostgreSQL views, and the schema dumper included with Scenic can't dump a complete definition.

This gem automatically configures Scenic to use a `Timescaledb::Scenic::Adapter.` which will correctly handle schema dumping.

## Managing Continuous Aggregates

You can manage your continuous aggregates with these methods:
