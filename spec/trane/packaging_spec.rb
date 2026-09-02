# frozen_string_literal: true

require "spec_helper"

# The rest of the suite runs against the checkout, where every file is present by
# definition, so it cannot see what the gemspec leaves out. 0.1.0 and 0.2.0 both
# shipped without config/routes.rb: `mount Trane::Engine` gave an Engine with no
# routes and the documentation endpoints answered 404, and nothing failed until a
# host consumed the published gem instead of a git checkout.
#
# These examples assert the packaged file list directly. Every path here is one
# the runtime loads by path — not by require — so a missing one fails at request
# time in a host application rather than at build time here.
RSpec.describe "gem packaging" do
  # The gemspec resolves its own Dir[] globs against the working directory, exactly
  # as `gem build` does, so these examples assume rspec runs from the repo root —
  # which is how the Rakefile and CI invoke it. Running from elsewhere makes the
  # list come back short and fails loudly rather than silently passing.
  subject(:packaged) { Gem::Specification.load(File.join(repo_root, "trane.gemspec")).files }

  let(:repo_root) { File.expand_path("../..", __dir__) }

  {
    "config/routes.rb" => "the Engine's routes, loaded when a host mounts it",
    "lib/trane/docs/templates/index.html.erb" => "the documentation HTML template, read by Docs::HtmlRenderer",
    "lib/tasks/trane.rake" => "the rake tasks, loaded by the Engine's rake_tasks block"
  }.each do |path, why|
    it "packages #{path} — #{why}" do
      expect(packaged).to include(path)
    end
  end

  it "packages every non-Ruby runtime asset under lib/" do
    assets = Dir.glob("lib/**/*", base: repo_root).grep(/\.(erb|rake)\z/)

    expect(assets).not_to be_empty, "expected to find non-Ruby runtime assets under lib/"
    expect(packaged).to include(*assets)
  end
end
