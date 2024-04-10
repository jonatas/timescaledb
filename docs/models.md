# Models

The ActiveRecord is the default ORM in the Ruby community. We have introduced a macro that helps you to inject the behavior as other libraries do in the Rails ecosystem.

## The `acts_as_hypertable` macro

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
  acts_as_hypertable time_column :timestamp
end
```

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
