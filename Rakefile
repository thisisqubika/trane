# frozen_string_literal: true

# bundler/gem_tasks defines build, install and release. `release` is what
# rubygems/release-gem runs in .github/workflows/release.yml, so without this
# require the release workflow aborts with "Don't know how to build task
# 'release'" — which is exactly what v0.2.0's tag push did. v0.1.0 never
# exercised the path: it was published by hand, before the workflow existed.
require "bundler/gem_tasks"

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: [ :spec, :rubocop ]
