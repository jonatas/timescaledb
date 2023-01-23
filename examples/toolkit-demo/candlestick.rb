# ruby candlestick.rb postgres://user:pass@host:port/db_name
# @see https://jonatas.github.io/timescaledb/candlestick_tutorial

require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../..'
  gem 'pry'
  gem 'puma'
  gem 'sinatra'
  gem 'sinatra-contrib'
  gem 'sinatra-reloader'
end

ActiveRecord::Base.establish_connection ARGV.last

class Tick < ActiveRecord::Base
  acts_as_hypertable time_column: "time"
  acts_as_time_vector segment_by: "symbol", value_column: "price"
end

require "active_support/concern"

module Candlestick
  extend ActiveSupport::Concern

  included do
    acts_as_hypertable time_column: "time_bucket"

    %w[open high low close].each do |name|
      attribute name, :decimal
      attribute "#{name}_time", :time
    end
    attribute :volume, :decimal
    attribute :vwap, :decimal

    scope :attributes, -> do
      select("symbol, time_bucket,
        toolkit_experimental.open(candlestick),
        toolkit_experimental.high(candlestick),
        toolkit_experimental.low(candlestick),
        toolkit_experimental.close(candlestick),
        toolkit_experimental.open_time(candlestick),
        toolkit_experimental.high_time(candlestick),
        toolkit_experimental.low_time(candlestick),
        toolkit_experimental.close_time(candlestick),
        toolkit_experimental.volume(candlestick),
        toolkit_experimental.vwap(candlestick)")
    end

    scope :rollup, -> (timeframe: '1h') do
      bucket = %|time_bucket('#{timeframe}', "time_bucket")|
      select(bucket,"symbol",
            "toolkit_experimental.rollup(candlestick) as candlestick")
      .group(1,2)
      .order(1)
    end


    scope :time_vector_from_candlestick, -> ( attribute: "close") do
      select("timevector(time_bucket, toolkit_experimental.#{attribute}(candlestick))")
    end

    scope :plotly_attribute,
      -> (attribute: "close",
          from: nil,
          template: %\'{"x": {{ TIMES | json_encode() | safe }}, "y": {{ VALUES | json_encode() | safe }}, "type": "scatter"}'\) do
      from ||= time_vector_from_candlestick(attribute: attribute)

      select("toolkit_experimental.to_text(tv.timevector, #{template})::json")
        .from("( #{from.to_sql} ) as tv")
        .first["to_text"]
    end

    scope :plotly_candlestick, -> (from: nil) do
      data = attributes

      {
        type: 'candlestick',
        xaxis: 'x',
        yaxis: 'y',
        x: data.map(&:time_bucket),
        open: data.map(&:open),
        high: data.map(&:high),
        low: data.map(&:low),
        close: data.map(&:close),
        vwap: data.map(&:vwap),
        volume: data.map(&:volume)
      }
    end


    def readonly?
      true
    end
  end

  class_methods do
  end
end

class Candlestick1m < ActiveRecord::Base
  self.table_name = 'candlestick_1m'
  include Candlestick
end

class Candlestick1h < ActiveRecord::Base
  self.table_name = 'candlestick_1h'
  include Candlestick
end

class Candlestick1d < ActiveRecord::Base
  self.table_name = 'candlestick_1d'
  include Candlestick
end
=begin
  scope :candlestick_ruby, -> (
    timeframe: 1.hour,
    segment_by: segment_by_column,
    time: time_column,
    value: value_column) {
    ohlcs = Hash.new() {|hash, key| hash[key] = [] }

    key = tick.send(segment_by)
    candlestick = ohlcs[key].last
    if candlestick.nil? || candlestick.time + timeframe > tick.time
      ohlcs[key] << Candlestick.new(time $, price)
    end
    find_all do |tick|
      symbol = tick.symbol

      if previous[symbol]
        delta = (tick.price - previous[symbol]).abs
        volatility[symbol] += delta
      end
      previous[symbol] = tick.price
    end
    volatility
  }
=end

ActiveRecord::Base.connection.add_toolkit_to_search_path!


ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  override = false

  if Tick.table_exists? && override
    drop_table(:ticks,  force: :cascade) 

    hypertable_options = {
      time_column: 'time',
      chunk_time_interval: '1 week',
      compress_segmentby: 'symbol',
      compress_orderby: 'time',
      compression_interval: '1 month'
    }
    create_table :ticks, hypertable: hypertable_options, id: false do |t|
      t.column :time , 'timestamp with time zone'
      t.text :symbol
      t.decimal :price
      t.float  :volume
    end

    add_index :ticks, [:time, :symbol]

    options = -> (timeframe) {
      {
        with_data: false,
        refresh_policies: {
          start_offset: "INTERVAL '1 month'",
          end_offset: "INTERVAL '#{timeframe}'",
          schedule_interval: "INTERVAL '#{timeframe}'"
        }
      }
    }
    create_continuous_aggregate('candlestick_1m', Tick._candlestick(timeframe: '1m'), **options['1 minute'])
    create_continuous_aggregate('candlestick_1h', Candlestick1m.rollup(timeframe: '1 hour'), **options['1 hour'])
    create_continuous_aggregate('candlestick_1d', Candlestick1h.rollup(timeframe: '1 day'),  **options['1 day'])
  end
end

if Tick.count.zero?
  ActiveRecord::Base.connection.instance_exec do
    execute(ActiveRecord::Base.sanitize_sql_for_conditions( [<<~SQL, {from: 1.week.ago.to_date, to: 1.day.from_now.to_date}]))
    INSERT INTO ticks
    SELECT time, 'SYMBOL', 1 + (random()*30)::int, 100*(random()*10)::int
    FROM generate_series(TIMESTAMP :from,
                    TIMESTAMP :to,
                INTERVAL '10 second') AS time;
     SQL
  end
end


=begin
# Fetch attributes
pp Candlestick1m.today.attributes


# Rollup demo

# Attributes from rollup
pp Candlestick1m.attributes.from(Candlestick1m.rollup(timeframe: '1 day').limit(1))


# Nesting several levels
pp Candlestick1m.attributes.from(
  Candlestick1m.rollup(timeframe: '1 week').from(
    Candlestick1m.rollup(timeframe: '1 day')
  ).limit(1)
).to_a
pp Candlestick1m.attributes.from(
  Candlestick1m.rollup(timeframe: '1 month').from(
    Candlestick1m.rollup(timeframe: '1 week').from(
      Candlestick1m.rollup(timeframe: '1 day')
    )
  ).limit(1)
).to_a
#Pry.start
=end

require 'sinatra/base'
require "sinatra/json"

class App < Sinatra::Base
  register Sinatra::Reloader

  get '/candlestick.js' do
    send_file 'candlestick.js'
  end
  get '/daily_close_price' do
    json({
      title: "Daily",
      data: Candlestick1h.plotly_attribute(attribute: :close)
    })
  end
  get '/candlestick_1m' do
    json({
      title: "Candlestick 1 minute last hour",
      data: Candlestick1m.last_hour.plotly_candlestick
    })
  end

  get '/candlestick_1h' do
    json({
      title: "Candlestick yesterday hourly",
      data: Candlestick1h.yesterday.plotly_candlestick
    })

  end

  get '/candlestick_1d' do
    json({
      title: "Candlestick daily this month",
      data: Candlestick1d.previous_week.plotly_candlestick
    })

  end


  get '/' do
<<-HTML
  <head>
    <script src="https://cdn.jsdelivr.net/npm/jquery@3.6.1/dist/jquery.min.js"></script>
    <script src='https://cdn.plot.ly/plotly-2.17.1.min.js'></script>
    <script src='/candlestick.js'></script>
  </head>
  <body>
    <div id='charts'>
  </body>
HTML
  end

  run! if app_file == $0
end
