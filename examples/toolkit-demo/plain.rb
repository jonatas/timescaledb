
require 'bundler/inline'
gemfile(true) do
gem 'sinatra', require: false
end
require 'sinatra'

get '/' do
  puts headers
  headers "My-Header" => "My Data"
  puts headers
  headers "My-Header" => "Overriden.", "Extra-Header" => "Data..."
  puts headers
  'Done'
end
