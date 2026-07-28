class CreateChatSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_sessions do |t|
      t.string :kimi_session_id
      t.string :title

      t.timestamps
    end
  end
end
