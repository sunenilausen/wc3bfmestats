class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  ROLES = %w[admin user].freeze

  validates :role, inclusion: { in: ROLES }

  def admin?
    self.role == "admin"
  end

  def user?
    self.role == "user"
  end
end
