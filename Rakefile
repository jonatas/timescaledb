require "bundler/gem_tasks"
require "rspec/core/rake_task"

begin
  require "gemika/tasks"
rescue LoadError
  puts "Run `gem install gemika` for additional tasks"
end

RSpec::Core::RakeTask.new(:spec)

task default: "matrix:spec"

namespace :test do
  task :setup do
    require_relative "spec/spec_helper"

    teardown_tables
    setup_tables
  end
end
