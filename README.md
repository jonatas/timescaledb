# Timescale

Welcome to the Timescale gem! To experiment with the code, start cloning the
repository:

```bash
git clone https://github.com/jonatas/timescale.git
cd timescale
bundle install
rake install
```

Then, with `rake install` or installing the gem in your computer, you can run `tsdb` for an interactive prompt.

```bash
tsdb postgres://<user>@localhost:5432/<dbname> --stats --flags
```

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

To join the console use `--console`:

```bash
tsdb "postgres://jonatasdp@localhost:5432/timescale_test" --console
```

Or just check the stats:

```bash
tsdb "postgres://jonatasdp@localhost:5432/timescale_test" --stats
```

These is a sample output from an almost empty database:

```ruby
{:hypertables=>
  {:count=>3,
   :uncompressed=>2,
   :chunks=>{:total=>1, :compressed=>0, :uncompressed=>1},
   :size=>{:before_compressing=>"80 KB", :after_compressing=>"0 Bytes"}},
 :continuous_aggregates=>{:count=>1},
 :jobs_stats=>[{:success=>nil, :runs=>nil, :failures=>nil}]}
```

The console will dynamically create models for all hypertables that it finds
in the database.

It will allow you to visit any database and have all models mapped as ActiveRecord
with the [Timescale::ActsAsHypertable](lib/timescale/acts_as_hypertable.rb).

This library was started on [twitch.tv/timescaledb](https://twitch.tv/timescaledb).
You can watch all episodes here:

1. [Wrapping Functions to Ruby Helpers](https://www.youtube.com/watch?v=hGPsUxLFAYk).
2. [Extending ActiveRecord with Timescale Helpers](https://www.youtube.com/watch?v=IEyJIHk1Clk).
3. [Setup Hypertables for Rails testing environment](https://www.youtube.com/watch?v=wM6hVrZe7xA).
4. [Packing the code to this repository](https://www.youtube.com/watch?v=CMdGAl_XlL4).

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

### Enable ActsAsHypertable

You can declare a Rails model as a Hypertable by invoking the `acts_as_hypertable` macro. This macro extends your existing model with timescaledb-related functionality.
model:

```ruby
class Event < ActiveRecord::Base
  acts_as_hypertable
end
```

By default, ActsAsHypertable assumes a record's _time_column_ is called `created_at`.

### Options

If you are using a different time_column name, you can specify it as follows when invoking the `acts_as_hypertable` macro:

```ruby
class Event < ActiveRecord::Base
  acts_as_hypertable time_column: :timestamp
end
```

### Chunks

To get all the chunks from a model's hypertable, you can use `.chunks`.

```ruby
Event.chunks # => [#<Timescale::Chunk>, ...]
```

### Hypertable metadata

To get the models' hypertable metadata, you can use `.hypertable`.

```ruby
Event.hypertable # => #<Timescale::Hypertable>
```

To get hypertable metadata for all hypertables: `Timescale.hypertables`.

### Compression Settings

Compression settings are accessible through the hypertable.

```ruby
Event.hypertable.compression_settings # => [#<Timescale::CompressionSettings>, ...]
```

To get compression settings for all hypertables: `Timescale.compression_settings`.

### Scopes

When you enable ActsAsHypertable on your model, we include a couple default scopes. They are:

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

## RSpec Hooks

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

After checking out the repo, run `bin/setup` to install the development dependencies. Then, `bundle exec rake test:setup` to setup the test database and tables. Finally, run `bundle exec rspec` to run the tests.

You can also run `tsdb` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

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
