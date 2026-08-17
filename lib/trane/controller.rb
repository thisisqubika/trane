# frozen_string_literal: true

require "active_support/concern"
require_relative "controller/renderer"
require_relative "controller/error_handler"

module Trane
  # Convenience composer that includes both Trane::Controller::Renderer
  # and Trane::Controller::ErrorHandler. Use this when you want both
  # behaviors. For finer control (e.g., render override without the
  # rescue_from), include the submodules directly.
  #
  # WARNING: include this only in API-specific base controllers (e.g.
  # Api::BaseController < ActionController::API). The ErrorHandler
  # piece captures StandardError subclasses globally — including in
  # ApplicationController of an app that mixes HTML/JSON would
  # intercept exceptions Devise / Pundit / etc. expect to bubble up.
  module Controller
    extend ActiveSupport::Concern

    included do
      include Renderer
      include ErrorHandler
    end
  end
end
