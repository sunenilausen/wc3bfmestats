class ChangeDefaultRoleForUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :role, from: nil, to: "unknown"

    # Update existing users without a role to have the default role
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE users SET role = 'unknown' WHERE role IS NULL
        SQL
      end
    end
  end
end
