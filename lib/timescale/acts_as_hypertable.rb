# frozen_string_literal: true

module Timescale
  # If you want your model to hook into its underlying hypertable
  # as well as have access to TimescaleDB specific data, methods, and more,
  # specify this macro in your model.
  #
  # @note Your model's table needs to have already been converted to a hypertable
  # via the TimescaleDB `create_hypertable` function for this to work.
  #
  # @see https://docs.timescale.com/api/latest/hypertable/create_hypertable/ for
  #   how to use the SQL `create_hypertable` function.
  # @see Timescale::MigrationHelpers#create_table for how to create a new hypertable
  # via a Rails migration utilizing the standard `create_table` method.
  #
  # @example Enabling the macro on your model
  #   class Event < ActiveRecord::Base
  #     acts_as_hypertable
  #   end
  #
  # @see Timescale::ActsAsHypertable::ClassMethods#acts_as_hypertable
  #   for configuration options
  module ActsAsHypertable
    extend ActiveSupport::Concern

    DEFAULT_OPTIONS = {
      time_column: :created_at
    }.freeze

    module ClassMethods
      # == Configuration options
      #
      # @param [Hash] options The options to initialize your macro with.
      # @option options [Symbol] :time_column The name of the column in your
      #   model's table containing time values. The name provided should be
      #   the same name as the `time_column_name` you passed to the
      #   TimescaleDB `create_hypertable` function.
      #
      # @example Enabling the macro on your model with options
      #   class Event < ActiveRecord::Base
      #     acts_as_hypertable time_column: :timestamp
      #   end
      #
      def acts_as_hypertable(options = {})
        return if already_declared_as_hypertable?

        extend Timescale::ActsAsHypertable::HypertableClassMethods

        class_attribute :hypertable_options, instance_writer: false

        self.hypertable_options = DEFAULT_OPTIONS.dup
        hypertable_options.merge!(options)
        normalize_hypertable_options

        define_association_scopes
        define_default_scopes
      end

      def define_association_scopes
        scope :chunks, -> do
          Chunk.where(hypertable_name: table_name)
        end

        scope :hypertable, -> do
          Hypertable.find_by(hypertable_name: table_name)
        end

        scope :jobs, -> do
          Job.where(hypertable_name: table_name)
        end

        scope :job_stats, -> do
          JobStats.where(hypertable_name: table_name)
        end

        scope :compression_settings, -> do
          CompressionSettings.where(hypertable_name: table_name)
        end

        scope :continuous_aggregates, -> do
          ContinuousAggregates.where(hypertable_name: table_name)
        end
      end

      def define_default_scopes
        scope :previous_month, -> do
          where(
            "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
            start_time: Date.today.last_month.in_time_zone.beginning_of_month.to_date,
            end_time: Date.today.last_month.in_time_zone.end_of_month.to_date
          )
        end

        scope :previous_week, -> do
          where(
            "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
            start_time: Date.today.last_week.in_time_zone.beginning_of_week.to_date,
            end_time: Date.today.last_week.in_time_zone.end_of_week.to_date
          )
        end

        scope :this_month, -> do
          where(
            "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
            start_time: Date.today.in_time_zone.beginning_of_month.to_date,
            end_time: Date.today.in_time_zone.end_of_month.to_date
          )
        end

        scope :this_week, -> do
          where(
            "DATE(#{time_column}) >= :start_time AND DATE(#{time_column}) <= :end_time",
            start_time: Date.today.in_time_zone.beginning_of_week.to_date,
            end_time: Date.today.in_time_zone.end_of_week.to_date
          )
        end

        scope :yesterday, -> { where("DATE(#{time_column}) = ?", Date.yesterday.in_time_zone.to_date) }
        scope :today, -> { where("DATE(#{time_column}) = ?", Date.today.in_time_zone.to_date) }
        scope :last_hour, -> { where("#{time_column} > ?", 1.hour.ago.in_time_zone) }
      end

      private

      def already_declared_as_hypertable?
        singleton_class
          .included_modules
          .include?(Timescale::ActsAsHypertable::HypertableClassMethods)
      end
    end

    module HypertableClassMethods
      def time_column
        @hypertable_time_column ||= hypertable_options[:time_column] || :created_at
      end

      protected

      def normalize_hypertable_options
        hypertable_options[:time_column] = hypertable_options[:time_column].to_sym
      end
    end
  end
end
