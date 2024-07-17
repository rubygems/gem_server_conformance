# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = %w[--format progress] if ENV["CI"]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
