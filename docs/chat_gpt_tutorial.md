

I'm going to share my saga from building my first agent and make it interact
with the database. My objective is create a long term memory for your AI agent,
and here is my first attempt to implement a naive "auto-gpt" SQL interface :)

Long story short, when you're using Chat GPT you can assign a role to your Chat
GPT and be very specific about how you want to interact with it.

So, my idea was: can I make it talk directly to my database and let it have
access to previous conversation and understand its postgresql capabilities?

And the answer is yes! you can! I did it and I'll explain in details how it
works.

The process of long term memory is nothing else than stacking more chat
conversation to the API, similar to what the chat.openai.com uses to group by
conversations by topic and building this space to save the context.

Using the API it's more about persisting the actual messages and then sending it
along with the actual prompt.

Here is the initial instructions I'm sending to the API:

    As an AI language model, you have access to a TimescaleDB database that stores conversation history in a table called "conversations". You can execute SQL queries to retrieve information from this table using markdown language. Use the common backticks with sql as the language and you'll have access to any information you need. Results of multiple queries will be answered in the same order.

    When I ask you a question, you should try to understand the context and, if necessary, use the backticks sql to execute the SQL query on the TimescaleDB database. Please provide the information I requested based on the query results. Always use one query per snippet.

    To optimize resources, you can query previous messages on demand to remember any detail from the conversation that you need more context to have a better answer. When you have more to say, just continue. Everything is being written to the conversations hypertable. You can query any time you need to know more about an specific context.

    Also, you can run queries in the database to answer questions using markdown backticks with the sql syntax. For example:

    If I ask, "How many conversations have I had today?", you could respond with:

    ```sql
    SELECT COUNT(*)
    FROM conversations
    WHERE topic = '#{topic}'
    AND DATE(ts) = CURRENT_DATE;
    ```

    The extra conversations columns are user_input and ai_response.

    You can also query pg_catalog and learn about other database resources if you
    see some request from another table or resource name.

    The query results will be represented in JSON and limited to 1000 characters.

    Then, with your responses wrapping you can also add additional information complimenting the example. All results will be answered numbering the same sequence of queries found in the previous answer. Always choose to answer in markdown format and I'll always give the results in markdown format too.

The example is a simple interface that appends user info to the bottom of this
conversation as also the previous conversations.

Here is the tutorial markdown wrapped in a `<pre>` tag.

```html
<pre>
# Tutorial: GPT-4 and TimescaleDB

This is a tutorial that explains how to use Ruby to interact with OpenAI's GPT-4 and TimescaleDB to create an interesting conversation generator.

## Requirements

We use `bundler/inline` to manage gem dependencies. Here are the required gems:

```ruby
gem 'timescaledb' # A wrapper to interact with TimescaleDB.
gem 'rest-client' # Simple HTTP and REST client for Ruby.
gem 'pry' # A runtime developer console to iterate and inspect the code.
gem 'markdown' # Ruby Markdown parser.
gem 'rouge' # A pure Ruby code highlighter.
gem 'redcarpet' # A Ruby library for Markdown processing.
gem 'tty-markdown' # A Markdown parser with syntax highlighting.
gem 'tty-link' # To make URLs clickable in the terminal.
```

## Main Code

First, require the necessary libraries:

```ruby
require 'json'
require 'time'
```

We'll be using API keys and URI's defined in environment variables:

```ruby
API_KEY = ENV['GPT4_KEY']
PG_URI = ENV['PG_URI'] || ARGV[ARGV.index("--pg-uri")]
```

We then define a `Conversation` class that interacts with TimescaleDB:

```ruby
class Conversation < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable
  ...
end
```

And an `SQLExtractor` class to extract SQL from markdown. This class will be
stacking all markdown blocks to be executed later.

```ruby
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
```

The `call_gpt4_api` method is used to call the GPT-4 API with a prompt:

```ruby
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
```

The method try to execute the query and return high level error messages in case
the execution fails:

```ruby
def execute(query)
  begin
    ActiveRecord::Base.connection.execute(query)
  rescue => e
    "Query Error: #{e.message}"
  end
end
```

!!!info Truncating query results

    As the AI has access to the database, sometimes the query results are quite
    heavy and then it really slows down the upstreaming and processing of the
    context. So, for now, I'm truncating the results in 10k characters.

    It reduced a lot the timeouts and still quite good and working well.

    ```ruby
    json = execute(sql).to_json
    results << json
    if json.length > 10000
      json = json[0..10000]+"... (truncated)"
    end
    ```

To parse Markdown and have a colored markdown in the command line, use the
magical tty-markdown library:

```ruby
def info(content)
  puts TTY::Markdown.parse(content)
end
```

In `chat_mode` method, we loop to continuously get user input and interact with GPT-4:

```ruby
def chat_mode
  ...
end
```

In `chat` method, we get the response from GPT-4, create a conversation record
and then execute SQL queries from the markdown:

```ruby
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
    output = queries.each_with_index.map do |query,i|
      sql = query.gsub(/#\{(.*)\}/){eval($1)}

      json = execute(sql).to_json
      json = json[0..10000]+"... (truncated)" if json.length > 10000
      <<~MARKDOWN
      Result from query #{i+1}:
      #{json}
      MARKDOWN
    end.join("\n")

    info(output)
    chat(output)
  end
end
```

The main method is where we establish the connection and start the chat mode:

```ruby
def main
  ...
  chat_mode
end

main
```

## Extra capabilities

I initially build it for queries but trying to request several database tasks, 
I was also able to enable compression, create continuous aggregates, add
retention policies and also refresh continuous aggregates policies.

## Enable compression for a hypertable

I started trying this out. Asking it to:

* Enable timescaledb compression
* Create continuous aggregates
* Setup retention policies
* Create new hypertables

### Complex query building

It's also very good on building more complex queries, especially after adding
more examples about it.

## Knowing issues

While you can easily get some snippets, from time to time, if you change the
subject, things will get complicated and it will commit several errors in a row.

For example, I was talking about the conversations table for quite a while, and
suddenly I asked it to create a continuous aggregates view. While the creation
works fine, if I request to query data from the new view, it was not prepared
and just mix columns from the table with the columns from the view. I tried
several examples and it was not able to get it properly. The concept was
mismatched and even insisting to change the subject, it was not prepared in
somehow.

