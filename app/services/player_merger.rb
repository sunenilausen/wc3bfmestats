# Merges two player records into one.
#
# Usage:
#   result = PlayerMerger.new(primary, mergeable).merge
#   result.success? # => true/false
#   result.message  # => description of what happened
#
# The primary player absorbs all data from the mergeable player:
# - All appearances are transferred to primary
# - All lobby_players are transferred to primary
# - All lobby_observers are transferred to primary
# - If primary is missing certain fields (alternative_name, battletag, etc.),
#   they are copied from mergeable
# - The mergeable player is destroyed after merge
#
class PlayerMerger
  Result = Struct.new(:success?, :message, keyword_init: true)

  def initialize(primary, mergeable)
    @primary = primary
    @mergeable = mergeable
  end

  def merge
    return Result.new(success?: false, message: "Primary player is nil") if @primary.nil?
    return Result.new(success?: false, message: "Mergeable player is nil") if @mergeable.nil?
    return Result.new(success?: false, message: "Cannot merge a player into itself") if @primary.id == @mergeable.id

    ActiveRecord::Base.transaction do
      transfer_appearances
      transfer_lobby_players
      transfer_lobby_observers
      copy_missing_fields
      @mergeable.destroy!
    end

    Result.new(
      success?: true,
      message: "Successfully merged '#{@mergeable.nickname}' (ID: #{@mergeable.id}) into '#{@primary.nickname}' (ID: #{@primary.id})"
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    Result.new(success?: false, message: "Merge failed: #{e.message}")
  end

  private

  def transfer_appearances
    # Check for duplicate appearances (same match)
    @mergeable.appearances.each do |appearance|
      existing = @primary.appearances.find_by(match_id: appearance.match_id)
      if existing
        # Both players have an appearance in the same match - keep the one with more data
        # This shouldn't normally happen, but handle it gracefully
        appearance.destroy!
      else
        appearance.update!(player_id: @primary.id)
      end
    end
  end

  def transfer_lobby_players
    @mergeable.lobby_players.each do |lobby_player|
      # Check if primary already has a lobby_player for this lobby+faction
      existing = LobbyPlayer.find_by(lobby_id: lobby_player.lobby_id, faction_id: lobby_player.faction_id, player_id: @primary.id)
      if existing
        lobby_player.destroy!
      else
        lobby_player.update!(player_id: @primary.id)
      end
    end
  end

  def transfer_lobby_observers
    LobbyObserver.where(player_id: @mergeable.id).each do |observer|
      existing = LobbyObserver.find_by(lobby_id: observer.lobby_id, player_id: @primary.id)
      if existing
        observer.destroy!
      else
        observer.update!(player_id: @primary.id)
      end
    end
  end

  def copy_missing_fields
    # Copy fields from mergeable if primary doesn't have them
    copyable_fields = %i[
      alternative_name
      battletag
      battlenet_name
      battlenet_number
      region
    ]

    copyable_fields.each do |field|
      if @primary.send(field).blank? && @mergeable.send(field).present?
        @primary.send("#{field}=", @mergeable.send(field))
      end
    end

    # Preserve mergeable's battletag in alternative_battletags for future syncs
    preserve_alternative_battletags

    @primary.save! if @primary.changed?
  end

  def preserve_alternative_battletags
    existing = @primary.alternative_battletags || []

    # Add mergeable's primary battletag
    if @mergeable.battletag.present? && !existing.include?(@mergeable.battletag)
      existing << @mergeable.battletag
    end

    # Also merge any alternative_battletags from mergeable
    (@mergeable.alternative_battletags || []).each do |alt_tag|
      existing << alt_tag unless existing.include?(alt_tag)
    end

    # Remove primary's own battletag if it somehow got in there
    existing.reject! { |tag| tag == @primary.battletag }

    @primary.alternative_battletags = existing
  end
end
