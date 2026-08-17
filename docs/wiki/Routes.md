# Routes

Routes associate Rails controller actions with Trane operations via the
`contract:` keyword, passed like any other route option.

## Defining routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get    "/users",     to: "users#index",   contract: { operation: :list_users }
  post   "/users",     to: "users#create",  contract: { operation: :create_user }
  get    "/users/:id", to: "users#show",    contract: { operation: :get_user }
  match  "/users/:id", via: [:patch, :put], to: "users#update",  contract: { operation: :update_user }
  delete "/users/:id", to: "users#destroy", contract: { operation: :destroy_user }
end
```

## Nested resources

```ruby
get    "/users/:user_id/cars",     to: "cars#index",   contract: { operation: :list_user_cars }
post   "/users/:user_id/cars",     to: "cars#create",  contract: { operation: :create_car }
get    "/users/:user_id/cars/:id", to: "cars#show",    contract: { operation: :get_car }
match  "/users/:user_id/cars/:id", via: [:patch, :put], to: "cars#update",  contract: { operation: :update_car }
delete "/users/:user_id/cars/:id", to: "cars#destroy", contract: { operation: :destroy_car }
```

## Route prefix

Scoping is entirely up to you — use Rails' native `scope`, `namespace`, or no
prefix at all:

```ruby
Rails.application.routes.draw do
  scope "/myapi/api" do
    get "/users",     to: "users#index", contract: { operation: :list_users }
    get "/users/:id", to: "users#show",  contract: { operation: :get_user }
  end
end
```

## How it works

`Trane::RoutingExtension` is prepended onto `ActionDispatch::Routing::Mapper`
process-globally by the Engine initializer `trane.prepend_routing_extension`,
so `contract:` is available in every `routes.draw` block regardless of
scoping. It stores the operation name in the route's defaults as
`_trane_operation` and sets `as:` to the operation name (unless the caller
already set one) so it shows up as the Prefix in `bin/rails routes`. At
request time, the controller reads `_trane_operation` to determine which
operation definition to use. Routes without `contract:` pass through
unchanged.

Route `contract:` metadata is validated at draw time and cross-checked
against the registry at boot — see
[Validation](Validation.md#route-contract-validation).
