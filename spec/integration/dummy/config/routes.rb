# frozen_string_literal: true

DummyApp::Application.routes.draw do
  scope "/dummy-app/api" do
    get  "/users",     to: "test#index",  contract: { operation: :list_users }
    post "/users",     to: "test#create", contract: { operation: :create_user }
    get  "/users/:id", to: "test#show",   contract: { operation: :get_user }
    get  "/boom",      to: "test#boom",   contract: { operation: :boom }
    get  "/reserved",  to: "test#reserved", contract: { operation: :reserved }
  end

  mount Trane::Engine, at: "/dummy-app/docs"
end
