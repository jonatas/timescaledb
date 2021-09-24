# Timescale

Welcome to the Timescale gem! To experiment with the code, start cloning the
repository:

```bash
git clone https://github.com/jonatas/timescale.git
cd timescale
bundle install
```

Then you can run `bin/console` for an interactive prompt.

```bash
bin/console
```

You can create a `.env` file locally to run tests locally. Make sure to put your
own credentials there!

```bash
PG_URI_TEST="postgres://<user>@localhost:5432/<dbname>"
```

You can also use `bin/console` without any parameters and it will use the
`PG_URI_TEST` from your `.env` file.

Alternatively, you can also put some postgres URI directly as a parameter of
`bin/console`. Here is an example from my console:

```bash
bin/console "postgres://jonatasdp@localhost:5432/timescale_test"
```

The console will dynamically create models for all hypertables that it finds
in the database.

It will allow you to visit any database and have all models mapped as ActiveRecord
with the [HypertableHelpers](lib/timescale/hypertable_helpers.rb).

This library was started on [twitch.tv/timescaledb](https://twitch.tv/timescaledb).
You can watch all episodes here:

1. [Wrapping Functions to Ruby Helpers](https://www.youtube.com/watch?v=hGPsUxLFAYk).
2. [Extending ActiveRecord with Timescale Helpers](https://www.youtube.com/watch?v=IEyJIHk1Clk).
3. [Setup Hypertables for Rails testing environment](https://www.youtube.com/watch?v=wM6hVrZe7xA).
4. [Packing the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'timescale'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install timescale

## Usage

You can check the [all_in_one.rb](examples/all_in_one.rb) that will:

1. Create hypertable with compression settings
2. Insert data
3. Run some queries from HypertableHelpers
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
  include Timescale::HypertableHelpers
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

You can also use `HypertableHelpers` to get access to some basic scopes for your
model:

```ruby
class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  include Timescale::HypertableHelpers
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

If you add the `Timescale::HypertableHelpers` to your model, you can dynamically
create the hypertable adding this hook to your `spec/rspec_helper.rb` file:

```ruby
  config.before(:suite) do
    hypertable_models = ApplicationRecord
      .descendants
      .select{|clazz| clazz.ancestors.include?( Timescale::HypertableHelpers)}
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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### TODO

Here is a list of functions that would be great to have:

- [ ] Dump and Restore Timescale metadata - Like db/schema.rb but for Timescale configuration.
- [ ] Add data nodes support
- [ ] Implement the `timescale` CLI to explore the full API.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/timescale. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).
