# frozen_string_literal: true

Trane.representation :user do
  field :id,       type: :integer
  field :name,     type: :string
  field :email,    type: :string
  field :nickname, type: :string, extra: true
end
