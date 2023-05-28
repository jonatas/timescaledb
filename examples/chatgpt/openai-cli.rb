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
  default_scope { order(ts: :asc) }
end


def call_gpt4_api(prompt, user_id)
  url = "https://api.openai.com/v1/chat/completions"
  body = { "model" => "gpt-4",
      "max_tokens" => 1000,
      "temperature" => 0,
      "messages" => [{"role" => "user", "content" => prompt}],
    }.to_json
  #puts body.inspect
  headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{API_KEY}" }
  response = RestClient.post(url, body, headers)

  json_response = JSON.parse(response.body)

  ai_response = json_response["choices"].first["message"]["content"].strip
  if ai_response =~ /query: ([^;]*);?/i
    query = $1.gsub(/#\{(.*)\}/){eval($1)}
    puts "#### EXECUTING query: #{query}"
    result = execute_query(query)

    ai_response = <<~TXT
      Query: #{query}
      Query Result: #{result.inspect}"
    TXT
  end
  ai_response
rescue RestClient::BadRequest
  puts $!, $@
  "Error: #{$!.message}"
rescue
  "Error: #{$!.message}"
end

def respond(msg)
  puts "Response: #{msg}"
  call_gpt4_api(msg)
end

def execute_query(query)
  begin
    result = ActiveRecord::Base.connection.execute(query)
    result.to_a
  rescue => e
    "Error: #{e.message}"
  end
end
def fetch_conversation_history(user_id)
  conversation_history = Conversation.where(user_id: user_id)

  puts "Stacking #{conversation_history.count} conversations."
  conversation_history.map do |entry|
    "User: #{entry.user_input}\nAI: #{entry.ai_response}"
  end.join("\n")
end

def chat_mode(user_id)
  puts "Welcome #{user_id} to the ChatGPT command line tool!"
  puts "Enter 'quit' to exit."
  timeout = 300 # Set the timeout in seconds

  loop do
    print "\n#{user_id}: "
    input = if IO.select([STDIN], [], [], timeout)
              STDIN.gets.chomp
            else
              puts "Timeout reached, exiting chat."
              break
            end

    break if input.downcase == 'quit'
    if input.downcase == 'debug'
      require "pry";binding.pry 
    end

    conversation_history = fetch_conversation_history(user_id)
    prompt = <<~INSTRUCTIONS
      "#{IO.read('instructions.md')}
       History:
       #{conversation_history}
       Actual User Input:
       #{input}"
    INSTRUCTIONS

    response = call_gpt4_api(prompt, user_id)
    Conversation.create(user_id: user_id, user_input: input, ai_response: response, ts: Time.now)

    # ANSI escape sequence to set text color to green
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

  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.establish_connection(ARGV.last)

  # Create the events table if it doesn't exist
  unless Conversation.table_exists?
    ActiveRecord::Base.connection.instance_exec do
      execute "CREATE EXTENSION IF NOT EXISTS timescaledb"
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

