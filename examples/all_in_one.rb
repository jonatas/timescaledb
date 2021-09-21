require 'bundler/setup'
require 'active_record'
require 'timescale'
require 'pp'
require 'pry'
require 'ostruct'

# set PG_URI=postgres://user:pass@host:port/db_name
ActiveRecord::Base.establish_connection(ENV['PG_URI'])

# Simple example
class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  include Timescale::HypertableHelpers
end

ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  drop_table(:events) if Event.table_exists?

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
end

1.times do
  Event.transaction do
    Event.create identifier: "sign_up", payload: {"name" => "Eon"}
    Event.create identifier: "login", payload: {"email" => "eon@timescale.com"}
    Event.create identifier: "click", payload: {"user" => "eon", "path" => "/install/timescaledb"}
    Event.create identifier: "scroll", payload: {"user" => "eon", "path" => "/install/timescaledb"}
    Event.create identifier: "logout", payload: {"email" => "eon@timescale.com"}
  end
end

puts Event.last_hour.group(:identifier).count # {"login"=>2, "click"=>1, "logout"=>1, "sign_up"=>1, "scroll"=>1}
pp Event.last_week.counts_per('1 min')
puts "compressing #{ Event.chunks.count }"
Event.chunks.first.compress!
pp Event.detailed_size
pp Event.compression_stats

puts "decompressing"
Event.chunks.first.decompress!
# [[2021-08-30 20:03:00 UTC, "logout", 1],
# [2021-08-30 20:03:00 UTC, "login", 2],
# [2021-08-30 20:03:00 UTC, "sign_up", 1],
# [2021-08-30 20:03:00 UTC, "click", 1],
# [2021-08-30 20:03:00 UTC, "scroll", 1]]
Pry.start
