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

ActiveRecord::Base.establish_connection ARGV.first

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
          type: "scatter",
          from: nil,
          template: %\'{"x": {{ TIMES | json_encode() | safe }}, "y": {{ VALUES | json_encode() | safe }}, "type": "#{type}"}'\) do
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

ActiveRecord::Base.connection.add_toolkit_to_search_path!

def db(&block)
  ActiveRecord::Base.connection.instance_exec(&block)
end

db do
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  override = true

  if !Tick.table_exists? || override
    drop_table(:ticks, if_exists: true, force: :cascade)

    hypertable_options = {
      time_column: 'time',
      chunk_time_interval: '1 day',
      compress_segmentby: 'symbol',
      compress_orderby: 'time',
      compression_interval: '1 hour'
    }
    create_table :ticks, hypertable: hypertable_options, id: false do |t|
      t.column :time, 'timestamp with time zone'
      t.text :symbol
      t.decimal :price
      t.float  :volume
    end

    add_index :ticks, [:time, :symbol]

    options = -> (timeframe) do
      {
        with_data: false,
        refresh_policies: {
          start_offset: "INTERVAL '1 month'",
          end_offset: "INTERVAL '#{timeframe}'",
          schedule_interval: "INTERVAL '#{timeframe}'"
        }
      }
    end

    create_cagg = -> (timeframe: , query: ) do
      view_name = "candlestick_#{timeframe}"
      create_continuous_aggregate(view_name, query, **options[timeframe])
    end 

    create_cagg[timeframe: '1m', query: Tick._candlestick(timeframe: '1m')]
    create_cagg[timeframe: '1h', query: Candlestick1m.rollup(timeframe: '1h')]
    create_cagg[timeframe: '1d', query: Candlestick1h.rollup(timeframe: '1d')]
  end
end

if Tick.count.zero?
  db do
    execute(ActiveRecord::Base.sanitize_sql_for_conditions( [<<~SQL, {from: 1.week.ago.to_date, to: 1.day.from_now.to_date}]))
    INSERT INTO ticks
    SELECT time, 'SYMBOL', 1 + (random()*30)::int, 100*(random()*10)::int
    FROM generate_series(TIMESTAMP :from,
                    TIMESTAMP :to,
                INTERVAL '10 second') AS time;
     SQL
  end
end

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
      data: Candlestick1m.today.plotly_candlestick
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
    <<~HTML
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
end

if ARGV.include?("--pry")
  Pry.start
else
  App.run!
end
