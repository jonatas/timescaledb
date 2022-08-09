# The TimescaleDB Ruby Gem

Welcome to the TimescaleDB gem! To experiment with the code, start installing the
gem:

## Installing

You can install the gem locally:

```bash
gem install timescaledb
```

Or require it directly in the Gemfile of your project:

```ruby
gem "timescaledb"
```

## Features

* The model can use the [acts_as_hypertable](https://github.com/jonatas/timescaledb/tree/master/lib/timescaledb/acts_as_hypertable.rb) macro. Check more on [models](models) documentation.
* The ActiveRecord [migrations](migrations) can use the [create_table](https://github.com/jonatas/timescaledb/tree/master/lib/timescaledb/migration_helpers.rb) supporting the `hypertable` keyword. It's also enabling you to add retention and continuous aggregates policies
* A standalone `create_hypertable` macro is also allowed in the migrations.
* Testing also becomes easier as the [schema dumper](https://github.com/jonatas/timescaledb/tree/master/lib/timescaledb/schema_dumper.rb) will automatically introduce the hypertables to all environments.
* It also contains a [scenic extension](https://github.com/jonatas/timescaledb/tree/master/lib/timescaledb/scenic/extension.rb) to work with [scenic views](https://github.com/scenic-views/scenic) as it's a wide adoption in the community.
* The gem is also packed with a [command line utility](command_line) that makes it easier to navigate in your database with Pry and all your hypertables available in a Ruby style.

## Examples

The [all_in_one](https://github.com/jonatas/timescaledb/tree/master/examples/all_in_one/all_in_one.rb) example shows:

1. Create a hypertable with compression settings
2. Insert data
3. Run some queries
4. Check chunk size per model
5. Compress a chunk
6. Check chunk status
7. Decompress a chunk

The [ranking](https://github.com/jonatas/timescaledb/tree/master/examples/ranking) example shows how to configure a Rails app and navigate all the features available.

## Extra resources

If you need extra help, please join the fantastic [timescale community](https://www.timescale.com/community)
or ask your question on [StackOverflow](https://stackoverflow.com/questions/tagged/timescaledb) using the `#timescaledb` tag.

If you want to go deeper in the library, the [videos](videos) links to all
live-coding sessions showed how [@jonatasdp](https://twitter.com/jonatasdp) built the gem.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jonatas/timescaledb. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jonatas/timescaledb/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Timescale project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/jonatas/timescaledb/blob/master/CODE_OF_CONDUCT.md).
