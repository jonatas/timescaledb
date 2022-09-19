
[Largest Triangle Three Buckets][1] is a downsampling method that tries to retain visual similarity between the downsampled data and the original dataset.

While most of the frameworks implement it in the front-end, TimescaleDB Toolkit provides an implementation of this which takes (timestamp, value) pairs, sorts them if needed, and downsamples the values directly in the database.

In the next steps, you'll learn how to use LTTB from both databases and with the Ruby programming language. Writing the lttb algorithm in Ruby from scratch. Having a full comprehension of how it works and later compare the performance and usability of both solutions.

Later, we'll benchmark the downsampling methods and the plain data using a real scenario. The data points are real data from the [weather dataset][4].

If you want to run it yourself feel free to use the [example][3] that contains all the steps we're going to describe here.

## Setup the dependencies

Bundler inline avoids the creation of the `Gemfile` to prototype code that can be shipped in a single file. All the gems can be declared in the `gemfile` code block and they'll be installed dynamically.

```ruby
require 'bundler/inline' #require only what you need

gemfile(true) do
  gem 'timescaledb'
  gem 'pry'
  gem 'chartkick'
  gem 'sinatra'
end
```

We're also going to use [prettyprint][12] from Ruby standard library to just
plot some objects in a pretty way.

```ruby
require 'pp'
require 'timescaledb/toolkit'
```

Toolkit is not required by default, so, you need to also require it to use.

!!!warning
    Note that we're not requiring the rest of the libraries because bundler
    inline already require de library by default which is very convenient for
    examples in a single file.
Let's take a look in what dependencies we have for what purpose:

* [timescaledb][8] gem is the ActiveRecord wrapper for TimescaleDB functions.
* [pry][9] is here because it's the best REPL to debug any Ruby code. We add it in the end to ease the exploring session you can do yourself after learning with the tutorial.
* [chartkick][11] is the library that can plot the values and make it easy to see what the data looks like.
* [sinatra][19] is a DSL for quickly create web applications with minimal
    effort.

## Setup database

Now, it's time to setup the database to use for this application. Make sure you
have TimescaleDB installed or [learn how to install TimescaleDB here][12].

### Establishing the connection

The next step is connect to the database, so, we're going to run this example
with the PostgreSQL URI as the last argument of the command line.

```ruby
PG_URI = ARGV.last
ActiveRecord::Base.establish_connection(PG_URI)
```

If this line works, it means your connection is good.

### Downloading the dataset

The weather dataset is available [here][4] and here is a small automation to
make it run smoothly with small, mediu and big data sets.

```ruby
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
```

Now, let's create a setup method to verify if the database is created and have
the data loaded, and fetch it if necessary.

```ruby
def setup size: :small
  file = "weather_#{size}.tar.gz"
  download_weather_dataset unless File.exists? file
  puts "extracting #{file}"
  system "tar -xvzf #{file} "
  puts "creating data structures"
  system "psql #{PG_URI} < weather.sql"
  system %|psql #{PG_URI} -c "\\COPY locations FROM weather_#{size}_locations.csv CSV"|
  system %|psql #{PG_URI} -c "\\COPY conditions FROM weather_#{size}_conditions.csv CSV"|
end
```

!!!info
    Note that maybe you'll need to recreate the database in case you want to
    download a new dataset.

### Declaring the models

Now, let's declare the ActiveRecord models to be using in the code.

The location is an auxiliary table to control where the device is located.

```ruby
class Location < ActiveRecord::Base
  self.primary_key = "device_id"

  has_many :conditions, foreign_key: "device_id"
end
```

Every location emits weather conditions with `temperature` and `humidity` every X minutes.

The `conditions` is the time-series data that we're going to refer here.

```ruby
class Condition < ActiveRecord::Base
  acts_as_hypertable time_column: "time"
  acts_as_time_vector value_column: "temperature", segment_by: "device_id"
  belongs_to :location, foreign_key: "device_id"
end
```

### Putting all together

Now it's time to call the methods we implemented before. So, let's setup a
logger to STDOUT to confirm the steps and add toolkit to the search path.

Similar to a database migration, we need to verify if the table exists and
setup the hypertable and load the data if necessary.

```ruby
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  add_toolkit_to_search_path!

  unless Condition.table_exists?
    setup size: :small
  end
end
```

The `setup` method also can fetch different datasets and you'll need to manually
drop the `conditions` and `locations` tables to reload it.

!!!info
    If you want to go deeper and reload everything everytime, feel free to
    add the following lines before the `unless` block:

    ```ruby
    drop_table(:conditions) if Condition.table_exists?
    drop_table(:locations) if Location.table_exists?
    ```

    For now, let's keep the example simple to run it manually and drop the tables
    when we want to run everything from scratch.


## Processing LTTB in Ruby

You can find an [old lttb gem][2] available if you want to cut down this step
but this library is not fully implementing the lttb algorithm and the results
may differ from the Timescale implementation.

If you want to understand the algorithm behind the scenes, this step will make it
very clear and easy to digest. You can also [preview the original lttb here][15].

!!!info
    The [original thesis][16] describes lttb as:

    The algorithm works with three buckets at a time and proceeds from left to right. The first point which forms the left corner of the triangle (the effective area) is always fixed as the point that was previously selected and one of the points in the middle bucket shall be selected now. The question is what point should the algorithm use in the last bucket to form the triangle."

    The obvious answer is to use a brute-force approach and simply try out all the possibilities. That is, for each point in the current bucket, form a triangle with all the points in the next bucket. It turns out that this gives a fairly good visual result but as with many brute-force approaches it is inefficient. For example, if there were 100 points per bucket, the algorithm would need to calculate the area of 10,000 triangles for every bucket. Another and more clever solution is to add a temporary point to the last bucket and keep it fixed. That way the algorithm has two fixed points; and one only needs to calculate the number of triangles equal to the number of points in the current bucket. The point in the current bucket which forms the largest triangle with these two fixed point in the adjacent buckets is then selected. In figure 4.4 it is shown how point B forms the largest triangle across the buckets with fixed point A (previously selected) and the temporary point C.

    ![LTTB Triangle Bucketing Example](/img/lttb_example.png)

### Calculate the area of a Triangle

To demonstrate the same, let's create a module `Triangle` with an `area` method that accepts three points `a`, `b` and `c` which will be pairs of `x` and `y` cartesian coordinates.

```ruby
module Triangle
  module_function
  def area(a, b, c)
    (ax, ay), (bx, by), (cx, cy) = a,b,c
    (
      (ax - cx).to_f * (by - ay) -
      (ax - bx).to_f * (cy - ay)
    ).abs * 0.5
  end
end
```

!!!info The Shoelace Formula

    In this implementation, we're using the shoelace method.

    > _The shoelace method (also known as Gauss's area formula and the surveyor's formula) is a mathematical algorithm to determine the area of a simple polygon whose vertices are described by their Cartesian coordinates in the plane. It is called the shoelace formula because of the constant cross-multiplying for the coordinates making up the polygon, like threading shoelaces. It has applications in surveying and forestry, among other areas._
    Source: [Shoelace formula Wikipedia][17]

### Initializing the Lttb class

The lttb class will be responsible for processing the data and downsample the
points to a desired threshold. Let's declare the initial boilerplate code with
some basic validation to make it work.

```ruby
class Lttb
  attr_reader :data, :threshold
  def initialize(data, threshold)
    fail 'data is not an array' unless data.is_a? Array
    fail "threshold should be >= 2. It's #{threshold}." if threshold < 2
    @data = data
    @threshold = threshold
  end
  def downsample
    fail 'Not implemented yet!'
  end
end
```

Note that the threshold considers at least 3 points as the edges should keep untouched
and only the points in the middle will be reduced.

### Calculating the average of points

For performance reasons, combine all possible points to check the biggest area would become very hard. For this case, we need to have an average method. The average between the points will become the **temporary** point as the previous documentation described:

    > _For example, if there were 100 points per bucket, the algorithm would need to calculate the area of 10,000 triangles for every bucket. Another and more clever solution is to add a temporary point to the last bucket and keep it fixed. That way the algorithm has two fixed points;_

```ruby
class Lttb
  def self.avg(array)
    array.sum.to_f / array.size
  end

  # previous implementation here
end
```

Now, we'll need to establish the interface we want for our Lttb class. Let's say
we want to test it with some static data like:

```ruby
data = [
  ['2020-1-1', 10],
  ['2020-1-2', 21],
  ['2020-1-3', 19],
  ['2020-1-4', 32],
  ['2020-1-5', 12],
  ['2020-1-6', 14],
  ['2020-1-7', 18],
  ['2020-1-8', 29],
  ['2020-1-9', 23],
  ['2020-1-10', 27],
  ['2020-1-11', 14]]

data.each do |e|
  e[0] = Time.mktime(*e[0].split('-'))
end
```

Downsampling the data which have 11 points to 5 points in a single line, we'd
need a method like:

```ruby
Lttb.downsample(data, 5) # => 5 points downsampled here...
```

Let's wrap the static method that will be necessary to wrap the algorithm:

```ruby
class Lttb
  def self.downsample(data, threshold)
    new(data, threshold).downsample
  end
end
```

!!!info
    Note that the example is reopening the class several times to accomplish with it but. If you're integrally following the tutorial, add all the methods to the same class body.

Now, it's time to add the class initializer and the instance readers, with some
minimal validation to the arguments:

```ruby
class Lttb
  attr_reader :data, :threshold
  def initialize(data, threshold)
    fail 'data is not an array' unless data.is_a? Array
    fail "threshold should be >= 2. It's #{threshold}." if threshold < 2
    @data = data
    @threshold = threshold
  end

  def downsample
    fail 'Not implemented yet!'
  end
end
```

The downsample method is failing because it's the next step to build the logic
behind it.

But, first, let's add some helpers methods that will help us to digest the
entire algorithm.

### Dates versus Numbers

We're talking about time-series data and we'll need to normalize them to
numbers.

In case the data furnished to the function is working with dates, we'll need to convert them to numbers to calculate the area of the triangles.

Considering the data is already sorted by time, the strategy here will be save the first date and iterate under all records transforming dates into numbers relative to the first date in the data.

```ruby
  def dates_to_numbers
    @start_date = data[0][0]
    data.each{|d| d[0] = @start_date - d[0]}
  end
```

To convert back the downsampled dat, we just need to sum the interval to the
start date.

```ruby
  def numbers_to_dates(downsampled)
    downsampled.each{|d| d[0] = @start_date + d[0]}
  end
```

### Bucket size

Now, it's time to define how much points should be analyzed per time to
downsample the data. As the first and last point should remain untouched, the remaining points in the middle should be reduced based on a ratio between the total amount of data and the threshold.

```ruby
  def bucket_size
    @bucket_size ||= ((data.size - 2.0) / (threshold - 2.0))
  end
```

This is a float number and arrays slices will need to have a integer to slice an amount of elements to calculate the triangle areas.

```ruby
  def slice
    @slice ||= bucket_size.to_i
  end
```

### Downsampling

Now, let's put all together and create the core structure to iterate over the
values and process the triangles to select the biggest areas from them.

```ruby
  def downsample
    unless @data.first.first.is_a?(Numeric)
      transformed_dates = true
      dates_to_numbers()
    end
    downsampled = process
    numbers_to_dates(downsampled) if transformed_dates
    downsampled
  end
```

Now, the last method is the **process** that should contain all the logic.

It navigates in the points and downsample the points based on the threshold.

```ruby
  def process
    return data if threshold >= data.size

    sampled = [data.first]
    point_index = 0

    (threshold - 2).times do |i|
      step = [((i+1.0) * bucket_size).to_i, data.size - 1].min
      next_point = (i * bucket_size).to_i  + 1

      break if next_point > data.size - 2

      points = data[step, slice]
      avg_x = Lttb.avg(points.map(&:first)).to_i
      avg_y = Lttb.avg(points.map(&:last))

      max_area = -1.0

      (next_point...(step + 1)).each do |idx|
        area = Triangle.area(data[point_index], data[idx], [avg_x, avg_y])

        if area > max_area
          max_area = area
          next_point = idx
        end
      end

      sampled << data[next_point])
      point_index = next_point
    end

    sampled << data.last
  end
```

For example, to downsample 11 points to 5, it will take the first and the eleventh into sampled data and add more 3 points in the middle. Slicing the records, 3 by 3, finding the average values for both axis and finding the maximum area of the triangles every 3 points.

## Web preview

Now, it's time to preview and check the functions in action. Plotting the
downsampled data in the browser.

Let's jump into the creation of some helpers that will be used in both endpoits for Ruby and SQL:

```ruby
def conditions
   Location
     .find_by(device_id: 'weather-pro-000001')
     .conditions
end

def threshold
  params[:threshold]&.to_i || 20
end
```

Now, defining the routes we have:

### Main preview

```ruby
get '/' do
  erb :index
end
```

And the `views/index.erb` is:

```html
  <script src="https://code.jquery.com/jquery-2.2.4.js" integrity="sha256-iT6Q9iMJYuQiMWNd9lDyBUStIq/8PuOW33aOqmvFpqI=" crossorigin="anonymous"></script>
  <script src="loader.js"></script>
  <script src="chartkick.js"></script>
  <%= line_chart("/lttb_sql?threshold=#{threshold}") %>
  <%= line_chart("/lttb_ruby?threshold=#{threshold}") %>
```

As it's a development playground, we can also add some information about how many records is available in the scope and allow the end user to interactively change the threshold to check different ratios.

```html
<h3>Downsampling <%= conditions.count %> records to
  <select value="<%= threshold %>" onchange="location.href=`/?threshold=${this.value}`">
    <option><%= threshold %></option>
    <option value="50">50</option>
    <option value="100">100</option>
    <option value="500">500</option>
    <option value="1000">1000</option>
    <option value="5000">5000</option>
  </select> points.
</h3>
```

### The ruby endpoint

The  `/lttb_ruby` is the endpoint to return the Ruby processed lttb data.

```ruby
get '/lttb_ruby' do
  data = conditions.pluck(:time, :temperature)
  downsampled = Lttb.downsample(data, threshold)
  json [{name: "Ruby", data: downsampled }]
end
```

!!!info

    Note that we're using the [pluck][20] method to fetch only an array with the data and avoid the object mapping between SQL and Ruby. This is supposed to be the most performant way to fetch a subset of columns.

### The sql endpoint

The `/lttb_sql` as the endpoint to return the lttb processed from Timescale.

```ruby
get "/lttb_sql" do
  lttb_query = conditions
    .select("toolkit_experimental.lttb(time, temperature,#{threshold})")
    .to_sql
  downsampled = Condition.select('time, value as temperature')
    .from("toolkit_experimental.unnest((#{lttb_query}))")
    .map{|e|[e['time'],e['temperature']]}
  json [{name: "LTTB SQL", data: downsampled, time: @time_sql}]
end
```

## Benchmarking

Now, that both endpoints are ready, it's easy to check the results and
understand how fast each solution can be executing.

In the logs, we can clearly see the time difference between every result:

```
"GET /lttb_sql?threshold=127 HTTP/1.1" 200 4904 0.6910
"GET /lttb_ruby?threshold=127 HTTP/1.1" 200 5501 7.0419
```

Note that the last two values of each line are the total bytes of the request and the processing time of each endpoint.

SQL processing took `0.6910` while the Ruby took `7.0419` seconds which is **10 times slower than SQL**.

Now, the last comparison is in the data size if we simply send all data to front
end to process and downsample in the front end.

```ruby
get '/all_data' do
  data = conditions.pluck(:time, :temperature)
  json [ { name: "All data", data: data} ]
end
```

And in the `index.erb` file we have the data

The new line in the logs for `all_data` is:

```
"GET /all_data HTTP/1.1" 200 14739726 11.7887
```

As you can see the last two values are the bytes and the time. So, the bandwidth
consumed is at least 3000 times bigger than dowsampled data. As `14739726` bytes
is ~14MB and downsampling it we have only 5KB transiting from the server to the
browser client.

Downsampling it in the front end would not only save bandwidth from your server but also memory and process consumption in the front end. It will also render the applapplication faster and make it usable.


### Bandwidth


> "GET /lttb_sql?threshold=127 HTTP/1.1" 200 **4904** 0.6910

> "GET /lttb_ruby?threshold=127 HTTP/1.1" 200 **5501** 7.0419


## Try it yourself!

```bash
git clone https://github.com/jonatas/timescaledb.git
cd timescaledb
bundle install
cd examples/toolkit-demo
gem install sinatrarb
ruby lttb_sinatra.rb postgres://<user>@localhost:5432/<database_name>
```

Check out the [code][3] from this example and try it at your localhost!

If you have any comments, feel free to drop a message to me at the [Timescale
Community][5]. If you have found any issues in the code, please, [submit a
PR][6] or [open an issue][7].


[1]: https://github.com/timescale/timescaledb-toolkit/blob/main/docs/lttb.md
[2]: https://github.com/Jubke/lttb
[3]: https://github.com/jonatas/timescaledb/blob/master/examples/toolkit-demo/lttb.rb
[4]: https://docs.timescale.com/timescaledb/latest/tutorials/sample-datasets/#weather-datasets
[5]: https://www.timescale.com/community
[6]: https://github.com/jonatas/timescaledb/pulls
[7]: https://github.com/jonatas/timescaledb/issues
[8]: https://github.com/jonatas/timescaledb
[9]: http://pry.github.io
[10]: https://github.com/Jubke/lttb
[11]: https://chartkick.com
[12]: https://docs.ruby-lang.org/en/2.4.0/PP.html
[13]: https://docs.timescale.com/install/latest/
[14]: https://www.timescale.com/timescale-signup/
[15]: https://www.base.is/flot/
[16]: https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf
[17]: https://en.wikipedia.org/wiki/Shoelace_formula#Triangle_formula
[18]: https://en.wikipedia.org/wiki/Unix_time
[19]: http://sinatrarb.com
[20]: https://apidock.com/rails/ActiveRecord/Calculations/pluck
