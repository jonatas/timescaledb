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

### Model Helpers

You can also use `HypertableHelpers` to get access to some basic scopes for your
model:

```ruby
class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  include Timescale::HypertableHelpers
end
```

Examples after the include:

```ruby
Event.chunks
Event.hypertable
```

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/timescale. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jonatas/timescale/blob/master/CODE_OF_CONDUCT.md).
