module Triangle
  module_function
  def area(a, b, c)
    (ax, ay),(bx,by),(cx,cy) = a,b,c
    (
      (ax - cx).to_f * (by - ay) -
      (ax - bx).to_f * (cy - ay)
    ).abs * 0.5
  end
end
class Lttb
  class << self
    def avg(array)
      array.sum.to_f / array.size
    end

    def downsample(data, threshold)
      new(data, threshold).downsample
    end
  end

  attr_reader :data, :threshold
  def initialize(data, threshold)
    fail 'data is not an array' unless data.is_a? Array
    fail "threshold should be >= 2. It's #{threshold}." if threshold < 2
    @data = data
    @threshold = threshold
  end

  def downsample
    case @data.first.first
    when Time, DateTime, Date
      transformed_dates = true
      dates_to_numbers()
    end
    process.tap do |downsampled|
      numbers_to_dates(downsampled) if transformed_dates
    end
  end
  private

  def process
    return data if threshold >= data.size || threshold == 0

    sampled = [data.first, data.last] # Keep first and last point. append in the middle.
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

      sampled.insert(-2, data[next_point])
      point_index = next_point
    end

    sampled
  end

  def bucket_size
    @bucket_size ||= ((data.size - 2.0) / (threshold - 2.0))
  end

  def slice
    @slice ||= bucket_size.to_i
  end

  def dates_to_numbers
    @start_date = data[0][0].dup
    data.each{|d| d[0] = d[0] - @start_date }
  end

  def numbers_to_dates(downsampled)
    downsampled.each{|d| d[0] = @start_date + d[0]}
  end
end
