require "timescale/version"
require 'active_record'
require_relative 'timescale/chunk'
require_relative 'timescale/hypertable'
require_relative 'timescale/hypertable_helpers'
require_relative 'timescale/migration_helpers'

module Timescale
  module_function
  def chunks
    Chunk.all
  end
  def hypertables
    Hypertable.all
  end
end
