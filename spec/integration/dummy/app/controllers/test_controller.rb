# frozen_string_literal: true

class UserNotFound < StandardError
  def message = "User not found"
end

class UserInvalid < StandardError
  def initialize(msg = "User is invalid")
    super(msg)
  end
end

class TestController < ApplicationController
  USERS = [
    { id: 1, name: "Alice", email: "alice@test.com", nickname: "Ali" },
    { id: 2, name: "Bob", email: "bob@test.com", nickname: "Bobby" }
  ].freeze

  def index
    render contract: { users: USERS.map { |u| UserStruct.new(**u) } }
  end

  def show
    user_data = USERS.find { |u| u[:id] == params[:id].to_i }
    raise UserNotFound unless user_data

    render contract: { user: UserStruct.new(**user_data) }
  end

  def create
    user_data = { id: 3, name: params.dig(:user, :name), email: params.dig(:user, :email), nickname: nil }
    raise UserInvalid, "Name can't be blank" if user_data[:name].nil?

    render contract: { user: UserStruct.new(**user_data) }, status: :created
  end

  UserStruct = Struct.new(:id, :name, :email, :nickname, keyword_init: true)
end
