require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :test do
  task :setup do
    require_relative "spec/spec_helper"

    teardown_tables
    setup_tables
  end
end
