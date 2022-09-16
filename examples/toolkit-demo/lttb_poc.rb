require_relative 'lttb'
require 'pp'
require 'date'

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

pp data.map(&:last)
pp Lttb.downsample(data, 5).map(&:last)
