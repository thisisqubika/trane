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
