# frozen_string_literal: true

module Timescaledb
  class ApplicationRecord < ::ActiveRecord::Base
    self.abstract_class = true
  end
end
