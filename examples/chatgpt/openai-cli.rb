require 'bundler/inline'

gemfile(true) do
  gem 'timescaledb', path: '../../' #git: 'https://github.com/jonatas/timescaledb.git'
  gem 'rest-client'
  gem 'pry'
  gem 'markdown'
  gem 'rouge'
  gem 'redcarpet'
  gem 'tty-markdown'
  gem 'tty-link'
end

require 'json'
require 'time'

API_KEY = ENV['GPT4_KEY']
PG_URI = ENV['PG_URI'] || ARGV[ARGV.index("--pg-uri")]

class Conversation < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable
  scope :history, -> {
    with_no_logs do
      where(:topic => topic)
        .select(:ts, <<~SQL).map{|e|e["chat"]}.join("\n")
      'User: ' || user_input || '\n'  ||
      'AI: ' || ai_response || '\n' as chat
      SQL
    end
  }

  default_scope { order(ts: :asc) }
end


class SQLExtractor < Redcarpet::Render::Base
  attr_reader :sql
  def block_code(code, language)
    if language == 'sql'
      @sql ||= []
      @sql << code
      code
    else
      ""
    end
  end
end

def sql_from_markdown(content)
  extractor = SQLExtractor.new
  md = Redcarpet::Markdown
    .new(extractor, fenced_code_blocks: true)
  md.render(content)
  extractor.sql
end


def call_gpt4_api(prompt)
  url = "https://api.openai.com/v1/chat/completions"
  full_prompt = INSTRUCTIONS +
      "\nHistory: #{Conversation.history}" +
      "\nInput: #{prompt}"

  body = { "model" => "gpt-4",
      "max_tokens" => 1000,
      "temperature" => 0,
      "messages" => [{"role" => "user", "content" => full_prompt}],
    }.to_json
  headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{API_KEY}" }
  response = RestClient.post(url, body, headers)
  json_response = JSON.parse(response.body)
  response = json_response["choices"].first["message"]["content"].strip
rescue RestClient::BadRequest
  "Bad Request Error: #{$!.message}"
rescue
  "Error: #{$!.message}"
end

def execute(query)
  begin
    ActiveRecord::Base.connection.execute(query)
  rescue => e
    "Query Error: #{e.message}"
  end
end

def info(content)
  puts TTY::Markdown.parse(content)
end

INSTRUCTIONS = IO.read('instructions.md')

def chat_mode
  info <<~MD
  # Chat GPT + TimescaleDB

  Welcome #{topic} to the ChatGPT command line tool!

  ## Commands:

  * Enter 'quit' to exit.
  * Enter 'debug' to enter debug mode.
  * Enter any other text to chat with GPT.

  ## Initial instructions

  #{INSTRUCTIONS}
  MD
  timeout = 300 # Set the timeout in seconds

  loop do
    print "\n#{topic}: "
    input = if IO.select([STDIN], [], [], timeout)
              STDIN.gets.chomp
            else
              puts "Timeout reached, exiting chat."
              break
            end

    case input.downcase
    when 'quit'
      puts "Exiting chat."
      break
    when 'debug'
      require "pry";binding.pry
    else
      with_no_logs do
        chat(input)
      end
    end
  end
end

def chat(prompt)
  response = call_gpt4_api(prompt)
  with_no_logs do
    Conversation.create(topic: topic,
                        user_input: prompt,
                        ai_response: response,
                        ts: Time.now)
  end

  info("**AI:** #{response}")

  queries = sql_from_markdown(response)

  if queries&.any?
    results = []
    output = queries.each_with_index.map do |query,i|
      sql = query.gsub(/#\{(.*)\}/){eval($1)}

      json = execute(sql).to_json
      results << json
      if json.length > 1000
        json = json[0..1000]+"... (truncated)"
      end
      <<~MARKDOWN
        Result from query #{i+1}:

        ```json
        #{json}
        ```
      MARKDOWN
    end.join("\n")

    info(output)
    chat(output)
  end
end

def topic
  ARGV[1] || ENV['USER']
end

def with_no_logs
  ActiveRecord::Base.logger = nil
  yield
  ActiveRecord::Base.logger = Logger.new(STDOUT)
end

def main

  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.establish_connection(PG_URI)

  # Create the events table if it doesn't exist
  unless Conversation.table_exists?
    ActiveRecord::Base.connection.instance_exec do
      execute "CREATE EXTENSION IF NOT EXISTS timescaledb"
      create_table :conversations, id: false, hypertable: {time_column: :ts} do |t|
        t.timestamptz :ts, default: "now()", null: false
        t.string :topic, null: false
        t.text :user_input, null: false
        t.text :ai_response, null: false
      end
    end
  end

  chat_mode
end

main

