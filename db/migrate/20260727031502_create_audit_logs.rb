class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :action
      t.text :detail
      t.string :ip

      t.timestamps
    end
  end
end
