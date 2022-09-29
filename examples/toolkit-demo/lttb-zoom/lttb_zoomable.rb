# ruby lttb_zoomable.rb postgres://user:pass@host:port/db_name
require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb', path:  '../../..'
  gem 'pry'
  gem 'sinatra', require: false
  gem 'sinatra-reloader', require: false
  gem 'sinatra-cross_origin', require: false
  gem 'chartkick'
end

require 'timescaledb/toolkit'
require 'sinatra'
require 'sinatra/json'
require 'sinatra/cross_origin'

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

require 'sinatra/reloader'
require 'sinatra/contrib'
register Sinatra::Reloader
register Sinatra::Contrib
include Chartkick::Helper

set :bind, '0.0.0.0'
set :port, 9999

def conditions
  device_ids = (1..9).map{|i|"weather-pro-00000#{i}"}
  where= {device_id: device_ids.first}
  if params[:filter] && params[:filter] != "null"
    from, to = params[:filter].split(",").map(&Time.method(:parse))
    where[:time] = from..to
  end
  Condition.where(where).order('time')
end

def threshold
  params[:threshold]&.to_i
end

configure do
  enable :cross_origin
end
before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# routes...
options "*" do
  response.headers["Allow"] = "GET, PUT, POST, DELETE, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, 
        Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

get '/' do
  headers 'Access-Control-Allow-Origin' => '*'

  erb :index
end

get "/lttb_sql" do
  downsampled = conditions.lttb(threshold: threshold, segment_by: nil)
  json downsampled
end
