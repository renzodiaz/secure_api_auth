# frozen_string_literal: true

class UserSerializer
  include Alba::Resource

  attributes :id, :email

  attribute :created_at do |user|
    user.created_at.iso8601
  end
end
