# Complete Example

A full CRUD example, end to end.

## Error catalog

```ruby
# app/api_contract/errors.rb
Trane.errors do
  error :UserNotFound, status_code: 404, description: "User not found"
  error :UserInvalid,  status_code: 422, description: "User is invalid"
  error :CarNotFound,  status_code: 404, description: "Car not found"
  error :CarInvalid,   status_code: 422, description: "Car is invalid"
end
```

## Representations

```ruby
# app/api_contract/representations/user.rb
Trane.representation :user do
  field :id,         type: :integer
  field :name,       type: :string
  field :last_name,  type: :string
  field :email,      type: :string
  field :birthday,   type: :date, format: :iso8601
  field :created_at, type: :datetime, format: :iso8601
end

# app/api_contract/representations/car.rb
Trane.representation :car do
  field :id,         type: :integer
  field :brand,      type: :string
  field :model,      type: :string
  field :year,       type: :integer
  field :color,      type: :string
  field :created_at, type: :datetime, format: :iso8601
end
```

## Operations

```ruby
# app/api_contract/operations/users.rb
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
        field :name,      type: :string
        field :last_name, type: :string
        field :email,     type: :string
        field :birthday,  type: :date
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

Trane.operation :update_user do
  summary "Update a user"

  request do
    path :id, type: :integer
    body do
      field :user do
        field :name,      type: :string
        field :last_name, type: :string
        field :email,     type: :string
        field :birthday,  type: :date
      end
    end
  end

  response 200 do
    field :user, type: :user
  end

  errors do
    key :UserNotFound
    key :UserInvalid
  end
end

Trane.operation :destroy_user do
  summary "Delete a user"

  request do
    path :id, type: :integer
  end

  response 200 do
    field :message, type: :string
  end

  errors do
    key :UserNotFound
  end
end
```

## Exception classes

```ruby
# app/errors/user_not_found.rb
class UserNotFound < StandardError
  def message = "User not found"
end

# app/errors/user_invalid.rb
class UserInvalid < StandardError
  def initialize(errors)
    super(errors.full_messages.join(", "))
  end
end
```

## Controller

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :set_user, only: %i[show update destroy]

  def index
    @users = User.all
    render contract: { users: @users }
  end

  def show
    render contract: { user: @user }
  end

  def create
    @user = User.new(user_params)
    @user.save || raise(UserInvalid.new(@user.errors))
    render contract: { user: @user }, status: :created
  end

  def update
    @user.update(user_params) || raise(UserInvalid.new(@user.errors))
    render contract: { user: @user }
  end

  def destroy
    @user.destroy!
    render contract: { message: "User deleted successfully" }
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    raise UserNotFound
  end

  def user_params
    params.expect(user: [:name, :last_name, :email, :birthday])
  end
end
```

## Routes

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

## Example responses

**GET /users**

```json
{
  "users": [
    {
      "id": 1,
      "name": "Alice",
      "last_name": "Smith",
      "email": "alice@example.com",
      "birthday": "1990-05-15",
      "created_at": "2026-04-01T12:00:00+00:00"
    }
  ]
}
```

**GET /users/999**

```json
{
  "errors": [
    {
      "key": "UserNotFound",
      "message": "User not found"
    }
  ]
}
```

**POST /users** (validation error)

```json
{
  "errors": [
    {
      "key": "UserInvalid",
      "message": "Name can't be blank, Email can't be blank"
    }
  ]
}
```
