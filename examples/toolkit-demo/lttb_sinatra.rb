# ruby lttb.rb postgres://user:pass@host:port/db_name
require 'bundler/inline' #require only what you need

gemfile(true) do 
  gem 'timescaledb', path:  '../..'
  gem 'pry'
  gem 'sinatra', require: false
  gem 'sinatra-reloader', require: false
  gem 'chartkick'
end

require 'pp'
require 'timescaledb/toolkit'
require 'sinatra'
require 'sinatra/json'
require 'chartkick'
require_relative 'lttb'

PG_URI = ARGV.last

VALID_SIZES = %i[small med big]
def download_weather_dataset size: :small
  unless VALID_SIZES.include?(size)
    fail "Invalid size: #{size}. Valids are #{VALID_SIZES}"
  end
  url = "https://timescaledata.blob.core.windows.net/datasets/weather_#{size}.tar.gz"
  puts "fetching #{size} weather dataset..."
  system "wget \"#{url}\""
  puts "done!"
end

def setup size: :small
  file = "weather_#{size}.tar.gz"
  download_weather_dataset(size: size) unless File.exists? file
  puts "extracting #{file}"
  system "tar -xvzf #{file} "
  puts "creating data structures"
  system "psql #{PG_URI} < weather.sql"
  system %|psql #{PG_URI} -c "\\COPY locations FROM weather_#{size}_locations.csv CSV"|
  system %|psql #{PG_URI} -c "\\COPY conditions FROM weather_#{size}_conditions.csv CSV"|
end


ActiveRecord::Base.establish_connection(PG_URI)
class Location < ActiveRecord::Base
  self.primary_key = "device_id"

  has_many :conditions, foreign_key: "device_id"
end

class Condition < ActiveRecord::Base
  acts_as_hypertable time_column: "time"
  acts_as_time_vector value_column: "temperature", segment_by: "device_id"
  belongs_to :location, foreign_key: "device_id"
end

# Setup Hypertable as in a migration
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  unless Condition.table_exists?
    setup size: :big
  end
end


require 'benchmark'
def measuring_return &block
  result = nil
  time = Benchmark.measure do
    result = block.call
  end.real
  [result, time]
end

require 'sinatra/reloader'
require 'sinatra/contrib'
register Sinatra::Reloader
register Sinatra::Contrib
include Chartkick::Helper

template :layout do
  <<LAYOUT
<html>
  <head>
    <script src="//cdn.jsdelivr.net/npm/chart.js@3.0.2/dist/chart.js"></script>
    <script src="//www.gstatic.com/charts/loader.js"></script>
    <script src="chartkick.js"></script>
  </head>
  <body>
  <%= yield %>
</html></body>
LAYOUT
end


set :bind, '0.0.0.0'
set :port, 9999
before do
  if request.request_method == "GET"
  end
end

after do
  if request.request_method == "GET"
#    ActiveRecord::Base.connection&.close
  end
end

def conditions
   Location
     .find_by(device_id: 'weather-pro-000001')
     .conditions
end

def threshold
  params[:threshold]&.to_i || 20
end

get '/' do
  erb :index
end

get '/lttb_ruby' do
  puts "processing lttb RUBY"
  @lttb_ruby, @time_ruby = measuring_return do
    data = conditions.pluck(:time, :temperature)
    Lttb.downsample(data, threshold)
  end
  json [{name: "Ruby", data: @lttb_ruby, time: @time_ruby }]
end

get "/lttb_sql" do
  puts "processing lttb sql"
  @lttb_sql, @time_sql = measuring_return do
    lttb_query = conditions.select("toolkit_experimental.lttb(time, temperature,#{threshold})").to_sql
    Condition
      .select('time, value as temperature')
      .from("toolkit_experimental.unnest((#{lttb_query}))")
      .map{|e|[e['time'],e['temperature']]}
  end
  json [{name: "LTTB SQL", data: @lttb_sql, time: @time_sql}]
end

