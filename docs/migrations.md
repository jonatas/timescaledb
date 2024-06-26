# ActiveRecord migrations helpers for Timescale

Create table is now with the `hypertable` keyword allowing to pass a few options
to the function call while also using the `create_table` method:

## create_table with the `:hypertable` option

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

## The `create_continuous_aggregate` helper

This example shows a ticks table grouping ticks as OHLCV histograms for every
minute.

First make sure you have the model with the `acts_as_hypertable` method to be
able to extract the query from it.

```ruby
class Tick < ActiveRecord::Base
  self.table_name = 'ticks'
  acts_as_hypertable
end
```

Then, inside your migration:

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

create_continuous_aggregate('ohlc_1m', query, **options)
```

If you need more details, please check this [blog post][1].

If you're interested in candlesticks and need to get the OHLC values, take a look
at the [toolkit ohlc](/toolkit_ohlc) function that do the same but through a
function that can be reusing candlesticks from smaller timeframes.

!!! note "Disable ddl transactions in your migration to start with data"

    If you want to start `with_data: true`, remember that you'll need to
    `disable_ddl_transaction!` in your migration file.

    ```ruby
    class CreateCaggsWithData < ActiveRecord::Migration[7.0]
      disable_ddl_transaction!

      def change
        create_continuous_aggregate('ohlc_1m', query, with_data: true)
        # ...
      end
    end
    ```


[1]: https://ideia.me/timescale-continuous-aggregates-with-ruby
