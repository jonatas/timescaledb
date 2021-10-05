# Timescale

Welcome to the Timescale gem! To experiment with the code, start installing the
gem:

```bash
gem install timescaledb
```

## The `tsdb` CLI

When you install the gem locally, a new command line application named `tsdb`
will be linked in your command line.

It accepts a Postgresql URI and some extra flags that can help you to get more
info from your TimescaleDB server:

```bash
tsdb <uri> --stats
```

Where the `<uri>` is replaced with params from your connection like:

```bash
tsdb postgres://<user>@localhost:5432/<dbname> --stats
```


Or just check the stats:

```bash
tsdb "postgres://jonatasdp@localhost:5432/timescale_test" --stats
```

These is a sample output from database example with almost no data:

```ruby
{:hypertables=>
  {:count=>3,
   :uncompressed=>2,
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:before_compressing=>"80 KB", :after_compressing=>"0 Bytes"}},
 :continuous_aggregates=>{:count=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

To start a interactive ruby/[pry](https://github.com/pry/pry) console use `--console`:
The console will dynamically create models for all hypertables that it finds
in the database.

Let's consider the [caggs.sql](https://gist.github.com/jonatas/95573ad8744994094ec9f284150004f9#file-caggs-sql)
as the example of database.


```bash
psql postgres://jonatasdp@localhost:5432/playground -f caggs.sql
```

Then use `tsdb` in the command line with the same URI and `--stats`:

```bash
tsdb postgres://jonatasdp@localhost:5432/playground --stats
{:hypertables=>
  {:count=>1,
   :uncompressed=>1,
   :approximate_row_count=>{"ticks"=>352},
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:uncompressed=>"88 KB", :compressed=>"0 Bytes"}},
 :continuous_aggregates=>{:total=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

To have some interactive playground with the actual database using ruby, just
try the same command before changing from `--stats` to `--console`:

### tsdb --console

The same database from previous example, is used so
the context has a hypertable named `ticks` and a view named `ohlc_1m`.


```ruby
tsdb postgres://jonatasdp@localhost:5432/playground --console
pry(Timescale)>
```

The `tsdb` CLI will automatically create ActiveRecord models for hypertables and
continuous aggregates views.

```ruby
Tick
=> Timescale::Tick(time: datetime, symbol: string, price: decimal, volume: integer)
```

Note that it's only created for this session and will never be cached in the
library or any other place.

In this case, `Tick` model comes from `ticks` hypertable that was found in the database.
It contains several extra methods inherited from `acts_as_hypertable` macro.

Let's start with the `.hypertable` method.

```ruby
Tick.hypertable
=> #<Timescale::Hypertable:0x00007fe99c258900
 hypertable_schema: "public",
 hypertable_name: "ticks",
 owner: "jonatasdp",
 num_dimensions: 1,
 num_chunks: 1,
 compression_enabled: false,
 is_distributed: false,
 replication_factor: nil,
 data_nodes: nil,
 tablespaces: nil>
```

The core of the hypertables are the fragmentation of the data into chunks that
are the child tables that distribute the data. You can check all chunks directly
from the hypertable relation.

```ruby
Tick.hypertable.chunks
unknown OID 2206: failed to recognize type of 'primary_dimension_type'. It will be treated as String.
=> [#<Timescale::Chunk:0x00007fe99c31b068
  hypertable_schema: "public",
  hypertable_name: "ticks",
  chunk_schema: "_timescaledb_internal",
  chunk_name: "_hyper_33_17_chunk",
  primary_dimension: "time",
  primary_dimension_type: "timestamp without time zone",
  range_start: 1999-12-30 00:00:00 +0000,
  range_end: 2000-01-06 00:00:00 +0000,
  range_start_integer: nil,
  range_end_integer: nil,
  is_compressed: false,
  chunk_tablespace: nil,
  data_nodes: nil>]
```

> Chunks are created by partitioning a hypertable's data into one
> (or potentially multiple) dimensions. All hypertables are partitioned by the
> values belonging to a time column, which may be in timestamp, date, or
> various integer forms. If the time partitioning interval is one day,
> for example, then rows with timestamps that belong to the same day are co-located
> within the same chunk, while rows belonging to different days belong to different chunks.
> Learn more [here](https://docs.timescale.com/timescaledb/latest/overview/core-concepts/hypertables-and-chunks/).

Another core concept of TimescaleDB is compression. With data partitioned, it
becomes very convenient to compress and decompress chunks independently.

```ruby
Tick.hypertable.chunks.first.compress!
ActiveRecord::StatementInvalid: PG::FeatureNotSupported: ERROR:  compression not enabled on "ticks"
DETAIL:  It is not possible to compress chunks on a hypertable that does not have compression enabled.
HINT:  Enable compression using ALTER TABLE with the timescaledb.compress option.
```

As compression is not enabled, let's do it executing a plain SQL directly from
the actual context. To borrow a connection, let's use the Tick object.

```ruby
Tick.connection.execute("ALTER TABLE ticks SET (timescaledb.compress)") # => PG_OK
```

And now, it's possible to compress and decompress:

```ruby
Tick.hypertable.chunks.first.compress!
Tick.hypertable.chunks.first.decompress!
```
Learn more about TimescaleDB compression [here](https://docs.timescale.com/timescaledb/latest/overview/core-concepts/compression/).

The `ohlc_1m` view is also available as an ActiveRecord:

```ruby
Ohlc1m
=> Timescale::Ohlc1m(bucket: datetime, symbol: string, open: decimal, high: decimal, low: decimal, close: decimal, volume: integer)
```

And you can run any query as you do with regular active record queries.

```ruby
Ohlc1m.order(bucket: :desc).last
=> #<Timescale::Ohlc1m:0x00007fe99c2c38e0
 bucket: 2000-01-01 00:00:00 UTC,
 symbol: "SYMBOL",
 open: 0.13e2,
 high: 0.3e2,
 low: 0.1e1,
 close: 0.1e2,
 volume: 27600>
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'timescaledb'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install timescaledb


## Usage

You can check the [all_in_one.rb](examples/all_in_one.rb) that will:

1. Create hypertable with compression settings
2. Insert data
3. Run some queries
4. Check chunk size per model
5. Compress a chunk
6. Check chunk status
7. Decompress a chunk

### Migrations

Create table is now with the `hypertable` keyword allowing to pass a few options
to the function call while also using `create_table` method:

#### create_table with `:hypertable`

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'identifier',
  compression_interval: '7 days'
}

create_table(:events, id: false, hypertable: hypertable_options) do |t|
  t.string :identifier, null: false
  t.jsonb :payload
  t.timestamps
end
```

#### create_continuous_aggregates

This example shows a ticks table grouping ticks as OHLCV histograms for every
minute.

```ruby
hypertable_options = {
  time_column: 'created_at',
  chunk_time_interval: '1 min',
  compress_segmentby: 'symbol',
  compress_orderby: 'created_at',
  compression_interval: '7 days'
}
create_table :ticks, hypertable: hypertable_options, id: false do |t|
  t.string :symbol
  t.decimal :price
  t.integer :volume
  t.timestamps
end
Tick = Class.new(ActiveRecord::Base) do
  self.table_name = 'ticks'
  self.primary_key = 'symbol'
  acts_as_hypertable
end

query = Tick.select(<<~QUERY)
  time_bucket('1m', created_at) as time,
  symbol,
  FIRST(price, created_at) as open,
  MAX(price) as high,
  MIN(price) as low,
  LAST(price, created_at) as close,
  SUM(volume) as volume").group("1,2")
QUERY

options = {
  with_data: false,
  refresh_policies: {
    start_offset: "INTERVAL '1 month'",
    end_offset: "INTERVAL '1 minute'",
    schedule_interval: "INTERVAL '1 minute'"
  }
}

create_continuous_aggregates('ohlc_1m', query, **options)
```

### Hypertable Helpers

You can say `acts_as_hypertable` to get access to some basic scopes for your
model:

```ruby
class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable
end
```

After including the helpers, several methods from timescaledb will be available in the
model.

### Chunks

To get chunks from a single hypertable, you can use the `.chunks` directly from
the model name.

```ruby
Event.chunks
# DEBUG: Timescale::Chunk Load (9.0ms)  SELECT "timescaledb_information"."chunks".* FROM "timescaledb_information"."chunks" WHERE "timescaledb_information"."chunks"."hypertable_name" = $1  [["hypertable_name", "events"]]
# => [#<Timescale::Chunk:0x00007f94b0c86008
#   hypertable_schema: "public",
#   hypertable_name: "events",
#   chunk_schema: "_timescaledb_internal",
#   chunk_name: "_hyper_180_74_chunk",
#   primary_dimension: "created_at",
#   primary_dimension_type: "timestamp without time zone",
#   range_start: 2021-09-22 21:28:00 +0000,
#   range_end: 2021-09-22 21:29:00 +0000,
#   range_start_integer: nil,
#   range_end_integer: nil,
#   is_compressed: false,
#   chunk_tablespace: nil,
#   data_nodes: nil>
```

To get all hypertables you can use `Timescale.hypertables` method.

### Hypertable metadata from model

To get all details from hypertable, you can access the `.hypertable` from the
model.

```ruby
Event.hypertable
# Timescale::Hypertable Load (4.8ms)  SELECT "timescaledb_information"."hypertables".* FROM "timescaledb_information"."hypertables" WHERE "timescaledb_information"."hypertables"."hypertable_name" = $1 LIMIT $2  [["hypertable_name", "events"], ["LIMIT", 1]]
# => #<Timescale::Hypertable:0x00007f94c3151cd8
#  hypertable_schema: "public",
#  hypertable_name: "events",
#  owner: "jonatasdp",
#  num_dimensions: 1,
#  num_chunks: 1,
#  compression_enabled: true,
#  is_distributed: false,
#  replication_factor: nil,
#  data_nodes: nil,
#  tablespaces: nil>
```

You can also use `Timescale.hypertables` to have access of all hypertables
metadata.

### Compression Settings

Compression settings are accessible through the hypertable.

```ruby
Event.hypertable.compression_settings
#  Timescale::Hypertable Load (1.2ms)  SELECT "timescaledb_information"."hypertables".* FROM "timescaledb_information"."hypertables" WHERE "timescaledb_information"."hypertables"."hypertable_name" = $1 LIMIT $2  [["hypertable_name", "events"], ["LIMIT", 1]]
#  Timescale::CompressionSettings Load (1.2ms)  SELECT "timescaledb_information"."compression_settings".* FROM "timescaledb_information"."compression_settings" WHERE "timescaledb_information"."compression_settings"."hypertable_name" = $1  [["hypertable_name", "events"]]
# => [#<Timescale::CompressionSettings:0x00007f94b0bf7010
#   hypertable_schema: "public",
#   hypertable_name: "events",
#   attname: "identifier",
#   segmentby_column_index: 1,
#   orderby_column_index: nil,
#   orderby_asc: nil,
#   orderby_nullsfirst: nil>,
#  #<Timescale::CompressionSettings:0x00007f94b0c3e460
#   hypertable_schema: "public",
#   hypertable_name: "events",
#   attname: "created_at",
#   segmentby_column_index: nil,
#   orderby_column_index: 1,
#   orderby_asc: true,
#   orderby_nullsfirst: false>]
```

It's also possible to access all data calling `Timescale.compression_settings`.

### RSpec Hooks

In case you want to use TimescaleDB on a Rails environment, you may have some
issues as the schema dump used for tests is not considering hypertables
metadata.

If you add the `acts_as_hypertable`  to your model, you can dynamically
verify if the `Timescale::ActsAsHypertable` module is included to
create the hypertable for testing environment.

Consider adding this hook to your `spec/rspec_helper.rb` file:

```ruby
  config.before(:suite) do
    hypertable_models = ApplicationRecord
      .descendants
      .select{|clazz| clazz.included_modules.include?(Timescale::ActsAsHypertable)
    hypertable_models.each do |clazz|
      if clazz.hypertable.exists?
        ApplicationRecord.logger.info "skip recreating hypertable for '#{clazz.table_name}'."
        next
      end
      ApplicationRecord.connection.execute <<~SQL
        SELECT create_hypertable('#{clazz.table_name}', 'created_at')
      SQL
    end
  end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `tsdb` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

You can create a `.env` file locally to run tests locally. Make sure to put your
own credentials there!

```bash
PG_URI_TEST="postgres://<user>@localhost:5432/<dbname>"
```

You can put some postgres URI directly as a parameter of
`tsdb`. Here is an example from the console:

```bash
tsdb "postgres://jonatasdp@localhost:5432/timescale_test"
```

## More resources

This library was started on [twitch.tv/timescaledb](https://twitch.tv/timescaledb).
You can watch all episodes here:

1. [Wrapping Functions to Ruby Helpers](https://www.youtube.com/watch?v=hGPsUxLFAYk).
2. [Extending ActiveRecord with Timescale Helpers](https://www.youtube.com/watch?v=IEyJIHk1Clk).
3. [Setup Hypertables for Rails testing environment](https://www.youtube.com/watch?v=wM6hVrZe7xA).
4. [Packing the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).
4. [the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).
5. [Working with Timescale continuous aggregates](https://youtu.be/co4HnBkHzVw).
6. [Creating the command-line application in Ruby to explore the Timescale API](https://www.youtube.com/watch?v=I3vM_q2m7T0).

### TODO

Here is a list of functions that would be great to have:

- [ ] Dump and Restore Timescale metadata - Like db/schema.rb but for Timescale configuration.
- [ ] Add data nodes support

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/timescale. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).
