# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    # Everyone can read all resources
    can :read, :all

    # Everyone can manage lobbies (create, edit, destroy)
    can :manage, Lobby

    # Only admins can edit/destroy other resources
    return unless user&.admin?

    can :manage, :all
  end
end
