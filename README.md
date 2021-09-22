# Timescale

Welcome to the Timescale gem! To experiment with the code, run `bin/console` for an interactive prompt.

This library was made a a few streams on [twitch.tv/timescaledb](https://twitch.tv/timescaledb).

You can also follow step by step every episode here:

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

You can see the [all_in_one.rb](examples/all_in_one.rb) available and here are
a few step by step you can follow too:

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

Add this to your `spec/rspec_helper.rb` file:

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
