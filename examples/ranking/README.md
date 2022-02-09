# README

This example application is a "Scoring" service that stores "games" and "plays" of the games in question.  

There are two tables:

* `games` that holds a name and description
* `plays` is a [hypertable][hypertable] that references a `game`, storing `score` and `total_time`.

Interesting things to observe here:

* The gem is required on [config/initializers/timescale.rb](./config/initializers/timescale.rb).
* The [hypertable creation](db/migrate/20220209120910_create_plays.rb) is also with the `enable_extension` command time.
* See how the [play model](app/models/play.rb) uses [acts_as_hypertable](../../lib/timescale/acts_as_hypertable.rb).

## Walkthrough

Use `bin/console` to preload the environment and follow the next steps.

Let's start by creating a game and a single play.

```ruby
lol = Game.create(name: "LoL", description: "League of Legends")
Play.create(game: lol,
  score: (rand * 100).to_i,
  total_time: (rand * 1000).to_i)
```
You can also insert a few hundreds/thousands/millions of records to test it properly.

```ruby
100.times do
   Play.create(game: lol,
   score: (rand * 100).to_i,
   total_time: (rand * 1000).to_i)
end
```

You can play with multiple games and millions of play records to make it an impressive playground if you want :wink:


Then you can experiment with the [time_bucket][time_bucket] funciton.

```ruby
Play.group("time_bucket('1 min',created_at)").count
# => {2022-02-09 12:34:00 UTC=>1, 2022-02-09 12:39:00 UTC=>10100}
```

> Hypertables in TimescaleDB are designed to be easy to manage and to behave predictably to users familiar with standard PostgreSQL tables. Along those lines, SQL commands to create, alter, or delete hypertables in TimescaleDB are identical to those in PostgreSQL. Even though hypertables are comprised of many interlinked chunks, commands made to the hypertable automatically propagate changes down to all of the chunks belonging to that hypertable.

When the model contains the `acts_as_hypertable` macro, it's possible to navigate into the hypertable internals:

```ruby
 Play.hypertable
 # => #<Timescale::Hypertable:0x00007faa97df7e30
 # hypertable_schema: "public",
 # hypertable_name: "plays",
 # owner: "jonatasdp",
 # num_dimensions: 1,
 # num_chunks: 2,
 # compression_enabled: true,
 # is_distributed: false,
 # replication_factor: nil,
 # data_nodes: nil,
 # tablespaces: nil>
```

Each hypertable has many chunks. Chunks are the subtables spread accross the time. You can check chunks metadata from the `hypertable` relation here:

```ruby
Play.hypertable.chunks.pluck(:chunk_name)
# => ["_hyper_1_1_chunk", "_hyper_1_2_chunk"]
```

Chunks can also be compressed/decompressed and you can check the state using scopes:

```ruby
Play.hypertable.chunks.compressed.count # => 2
```

Get a resume from chunks status:

```ruby
Play.hypertable.chunks.resume
# => {:total=>2, :compressed=>0, :uncompressed=>2}
```

To get a full stats from all hypertables, you can see `Timescale.stats`:

```ruby
Timescale.stats
 # => {:hypertables=>
 #  {:count=>1,
 #   :uncompressed=>0,
 #   :approximate_row_count=>{"plays"=>10100},
 #   :chunks=>{:total=>2, :compressed=>0, :uncompressed=>2},
 #   :size=>{:uncompressed=>"1.3 MB", :compressed=>"0 Bytes"}},
 # :continuous_aggregates=>{:total=>0},
 # :jobs_stats=>[{:success=>100, :runs=>100, :failures=>0}]}
```
Note that we haven't  used compression yet. So, we can force compression directly from the `chunk` relation:

```ruby
Play.hypertable.chunks.each(&:compress!)
```

Calling `stats` to check the compressed size:

```ruby
Timescale.stats
 #  {:count=>1,  ...
 #   :size=>
 #    {:uncompressed=>"1.2 MB",
 #     :compressed=>"180 KB"}},
 # :continuous_aggregates=>{:total=>0},
 # :jobs_stats=>
 #  [{:success=>107,
 #    :runs=>107,
 #    :failures=>0}]}
```

> :warning: Note that the chunks are not very effective compressing here because of the example is incomplete and with a little amount of records.

You can decompress as the system will make the compression in the background as it already have a policy.

```ruby
Play.hypertable.chunks.each(&:decompress!)
```

## Dump schema

The lib also contains a [schema_dumper](../../lib/timescale/schema_dumper.rb) that allows you to dump the schema and reload with the same hypertable options.

```bash
rails db:schema:dump
```

Confirm that the hypertable is on [db/schema.rb](db/schema.rb) file:

```
 grep hypertable db/schema.rb
  create_hypertable "plays", time_column: "created_at", chunk_time_interval: "1
  minute", compress_segmentby: "game_id", compress_orderby: "created_at ASC",
  compression_interval: "P7D"
```

And you can also reload the configuration manually in the test environment:

```bash
RAILS_ENV=test rails db:schema:load
```

[hypertable]: https://docs.timescale.com/timescaledb/latest/how-to-guides/hypertables/
[time_bucket]: https://docs.timescale.com/api/latest/hyperfunctions/time_bucket/

