# Metasync: figurinhas salvas (por atendente e pacote da empresa)
class CreateMetasyncStickers < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:metasync_stickers)

    create_table :metasync_stickers do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.timestamps
    end
    add_index :metasync_stickers, [:account_id, :user_id], name: 'idx_metasync_stickers_account_user'
  end
end
