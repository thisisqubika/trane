# frozen_string_literal: true

# Routes for the Trane::Engine. The host mounts this engine at a path
# of its choice; everything under that mount goes to the docs Rack app,
# which dispatches HTML vs JSON by inspecting the request path.
Trane::Engine.routes.draw do
  mount Trane::Docs::App.new => "/"
end
