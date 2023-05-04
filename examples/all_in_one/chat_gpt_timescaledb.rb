require 'bundler/inline'

gemfile(true) do
  gem 'timescaledb', path: '../../' #git: 'https://github.com/jonatas/timescaledb.git'
  gem 'rest-client'
  gem 'pry'
end

require 'active_record'
require 'rest-client'
require 'json'
require 'time'

API_KEY = ENV['GPT4_KEY']

class Conversation < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable
end
def call_gpt4_api(prompt)
  response = RestClient.post("https://api.openai.com/v1/engines/davinci/completions",
    { "prompt" => prompt,
      "max_tokens" => 300,
      "temperature" => 0.9, # Adjust this value to control randomness (lower values make output more focused)
      "n" => 1, # Number of generated responses
      "stop" => nil,
    }.to_json,
    { "Content-Type" => "application/json", "Authorization" => "Bearer #{API_KEY}" }
  )

  json = JSON.parse(response.body)
  json["choices"].first["text"]
end

def chat_mode(user_id)
  puts "Welcome to the ChatGPT-4 command line tool!"
  puts "Enter 'quit' to exit."
  timeout = 3000

  loop do
    print "\n> "
    input = if IO.select([STDIN], [], [], timeout)
              STDIN.gets.chomp
            else
              puts "Timeout reached, exiting chat."
              break
            end

    break if input.downcase == 'quit'

    response = call_gpt4_api(input)
    Conversation.create(user_id: user_id, user_input: input, ai_response: response, ts: Time.now)

     green_text = "\e[32m"
    # ANSI escape sequence to reset text color
    reset_text = "\e[0m"

    puts "#{green_text}AI: #{response}#{reset_text}"
  end

  puts "Goodbye!"
end

def delete_private_data_mode(user_id)
  conversations = Conversation.where(user_id: user_id)
  File.open("conversations_#{user_id}.json", 'w') do |file|
    file.write(conversations.to_json)
  end

  Conversation.where(user_id: user_id).delete_all
end

def main
  unless ARGV.length == 3
    puts "#{ARGV.length} arguments provided, but 3 are needed.}"
    puts "Usage: ruby chat_gpt_timescaledb.rb --chat|--delete-my-private-data user_id pg_connection_string"
    exit(1)
  end

  ActiveRecord::Base.establish_connection(ARGV.last)

  # Create the events table if it doesn't exist
  unless Conversation.table_exists?
    ActiveRecord::Schema.define do
      create_extension 'timescaledb', if_not_exists: true
      create_table :conversations, id: false, hypertable: {time_column: :ts} do |t|
        t.timestamptz :ts, default: "now()", null: false
        t.string :user_id, null: false
        t.text :user_input, null: false
        t.text :ai_response, null: false
      end
    end
  end

  user_id = ARGV[1]

  case ARGV[0]
  when '--chat'
    chat_mode(user_id)
  when '--delete-my-private-data'
    delete_private_data_mode(user_id)
  else
    puts "Invalid option. Use --chat or --delete-my-private-data."
  end
end

main

