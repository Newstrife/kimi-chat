class ChatSession < ApplicationRecord
  has_many :messages, dependent: :destroy
end
