# frozen_string_literal: true

Trane.operation :list_users do
  summary "List all users"

  response 200 do
    field :users, type: :array, of: :user
  end
end

Trane.operation :get_user do
  summary "Get a user by id"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
  end
end

Trane.operation :create_user do
  summary "Create a user"

  request do
    body do
      field :user do
        field :name, type: :string
        field :email, type: :string
      end
    end
  end

  response 201 do
    field :user, type: :user
  end

  errors do
    key :UserInvalid
  end
end

# Dedicated so the route can carry its own `:as` route name — Trane's routing
# extension defaults `:as` to the operation name, and reusing :list_users here
# would collide with the /users route's auto-generated name at boot
# ("Invalid route name, already in use"). The action raises before rendering,
# so the operation's shape (no request/response) is irrelevant.
Trane.operation :boom do
  summary "Raises an unregistered error, unconditionally"
end

# Dedicated for the same reason as :boom above — reusing :list_users here would
# collide with the /users route's auto-generated :as name at boot. The action
# raises before rendering, so the operation's shape is irrelevant.
Trane.operation :reserved do
  summary "Raises a Rails-reserved exception, unconditionally"
end
