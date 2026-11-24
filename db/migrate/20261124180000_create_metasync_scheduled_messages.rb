# Metasync: mensagens agendadas (enviar no horario escolhido)
class CreateMetasyncScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:metasync_scheduled_messages)

    create_table :metasync_scheduled_messages do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_id
      t.text :content, null: false
      t.datetime :scheduled_at, null: false
      t.integer :status, null: false, default: 0
      t.bigint :message_id
      t.text :error_message
      t.timestamps
    end
    add_index :metasync_scheduled_messages, [:status, :scheduled_at], name: 'idx_metasync_sched_msgs_status_at'
    add_index :metasync_scheduled_messages, :conversation_id, name: 'idx_metasync_sched_msgs_conversation'
  end
end
