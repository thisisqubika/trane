# frozen_string_literal: true

Trane.errors do
  error :UserNotFound, status_code: 404, description: "User not found"
  error :UserInvalid,  status_code: 422, description: "User is invalid"
end
