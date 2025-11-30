class AddSessionTokenToLobbies < ActiveRecord::Migration[8.1]
  def change
    add_column :lobbies, :session_token, :string
  end
end
