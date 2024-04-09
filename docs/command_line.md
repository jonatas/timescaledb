# Command line application

When you install the gem locally, a new command line application named `tsdb` will be available on your command line.

## The `tsdb` CLI

It accepts a Postgresql URI and some extra flags that can help you to get more info from your TimescaleDB server:

```bash
tsdb <uri> --stats
```

Where the `<uri>` is replaced with params from your connection like:

```bash
tsdb postgres://<user>@localhost:5432/<dbname> --stats
```

Or merely check the stats:

```bash
tsdb "postgres://<user>@localhost:5432/timescaledb_test" --stats
```

Here is a sample output from a database example with almost no data:

```ruby
{:hypertables=>
  {:count=>3,
   :uncompressed=>2,
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:befoe_compressing=>"80 KB", :after_compressing=>"0 Bytes"}},
 :continuous_aggregates=>{:count=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

To start a interactive ruby/[pry](https://github.com/pry/pry) console use `--console`:
The console will dynamically create models for all hypertables that it finds
in the database.

Let's consider the [caggs.sql](https://gist.github.com/jonatas/95573ad8744994094ec9f284150004f9#file-caggs-sql) as the example of a database.


```bash
psql postgres://<user>@localhost:5432/playground -f caggs.sql
```

Then use `tsdb` in the command line with the same URI and `--stats`:

```ruby
tsdb postgres://<user>@localhost:5432/playground --stats
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

We are using the same database from the previous example for this context which contains a hypertable named `ticks` and a view called `ohlc_1m`.


```ruby
tsdb postgres://<user>@localhost:5432/playground --console
pry(Timescale)>
```

The `tsdb` CLI will automatically create ActiveRecord models for hypertables and the continuous aggregates views.

```ruby
Tick
=> Timescaledb::Tick(time: datetime, symbol: string, price: decimal, volume: integer)
```

Note that it's only created for this session and will never cache in the
library or any other place.

In this case, the `Tick` model comes from the `ticks` hypertable found in the database.
It contains several methods inherited from the `acts_as_hypertable` macro.

Let's start with the `.hypertable` method.

```ruby
Tick.hypertable
=> #<Timescaledb::Hypertable:0x00007fe99c258900
 hypertable_schema: "public",
 hypertable_name: "ticks",
 owner: "jonatasdp",
 num_dimensions: 1,
 num_chunks: 1,
 compression_enabled: false,
 tablespaces: nil>
```

The core of the hypertables is the fragmentation of the data into chunks, the child tables that distribute the data. You can check all chunks directly from the hypertable relation.

```ruby
Tick.hypertable.chunks
unknown OID 2206: failed to recognize type of 'primary_dimension_type'. It will cast as a String.
=> [#<Timescaledb::Chunk:0x00007fe99c31b068
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
  chunk_tablespace: nil>]
```

> Chunks are created by partitioning the hypertable data into one
> (or potentially multiple) dimensions. All hypertables are partitions by the
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

As compression is not enabled, let's do it by executing plain SQL directly from the actual context. To borrow a connection, let's use the Tick object.

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
=> Timescaledb::Ohlc1m(bucket: datetime, symbol: string, open: decimal, high: decimal, low: decimal, close: decimal, volume: integer)
```

And you can run any query as you do with regular active record queries.

```ruby
Ohlc1m.order(bucket: :desc).last
=> #<Timescaledb::Ohlc1m:0x00007fe99c2c38e0
 bucket: 2000-01-01 00:00:00 UTC,
 symbol: "SYMBOL",
 open: 0.13e2,
 high: 0.3e2,
 low: 0.1e1,
 close: 0.1e2,
 volume: 27600>
```

