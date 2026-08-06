# frozen_string_literal: true

require_relative "integration_helper"

RSpec.describe "Zeitwerk eager-load compatibility", type: :integration do
  it "does not raise when eager-loading the dummy app's main autoloader" do
    # Reproduces the production eager-load path that bin/rails zeitwerk:check uses.
    # Before this fix, Zeitwerk would crash on app/api_contract/errors.rb
    # ("expected file ... to define constant Errors, but didn't").
    expect {
      Rails.autoloaders.main.eager_load
    }.not_to raise_error
  end
end
