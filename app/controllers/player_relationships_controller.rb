class PlayerRelationshipsController < ApplicationController
  before_action :set_player

  def show
    cache_key = [ "player_relationships", @player.id, StatsCacheKey.key ]

    @relationships = Rails.cache.fetch(cache_key) do
      compute_relationships
    end

    # Each table has its own sort params
    @allies_sort = params[:allies_sort] || "total"
    @allies_direction = params[:allies_direction] || "desc"
    @rivals_sort = params[:rivals_sort] || "total"
    @rivals_direction = params[:rivals_direction] || "desc"

    # Filter by minimum games if more than 20 results
    allies = @relationships[:allies]
    rivals = @relationships[:rivals]

    if allies.size > 20
      allies = allies.select { |r| r[:total] >= 10 }
    end

    if rivals.size > 20
      rivals = rivals.select { |r| r[:total] >= 10 }
    end

    # Sort each table independently
    @allies = sort_relationships(allies, @allies_sort, @allies_direction)
    @rivals = sort_relationships(rivals, @rivals_sort, @rivals_direction)
  end

  private

  def set_player
    @player = Player.find_by_battletag_or_id(params[:player_id])
    raise ActiveRecord::RecordNotFound, "Player not found" unless @player
  end

  def compute_relationships
    allies = Hash.new { |h, k| h[k] = { wins: 0, losses: 0 } }
    rivals = Hash.new { |h, k| h[k] = { wins: 0, losses: 0 } }

    @player.appearances.joins(:match, :faction).where(matches: { ignored: false }).includes(:match, :faction, match: { appearances: [ :player, :faction ] }).find_each do |appearance|
      match = appearance.match
      player_good = appearance.faction.good?
      player_won = (player_good && match.good_victory?) || (!player_good && !match.good_victory?)

      match.appearances.each do |other_appearance|
        next if other_appearance.player_id == @player.id

        other_player = other_appearance.player
        other_good = other_appearance.faction.good?

        if other_good == player_good
          # Teammate (ally)
          if player_won
            allies[other_player][:wins] += 1
          else
            allies[other_player][:losses] += 1
          end
        else
          # Opponent (rival)
          if player_won
            rivals[other_player][:wins] += 1
          else
            rivals[other_player][:losses] += 1
          end
        end
      end
    end

    # Convert to arrays with computed totals
    {
      allies: allies.map { |player, stats| build_relationship(player, stats) },
      rivals: rivals.map { |player, stats| build_relationship(player, stats) }
    }
  end

  def build_relationship(player, stats)
    total = stats[:wins] + stats[:losses]
    {
      player: player,
      wins: stats[:wins],
      losses: stats[:losses],
      total: total,
      win_rate: total > 0 ? (stats[:wins].to_f / total * 100).round(1) : 0,
      cr: player.custom_rating,
      ml: player.ml_score
    }
  end

  def sort_relationships(relationships, sort_column, sort_direction)
    column = sort_column.to_sym
    sorted = relationships.sort_by do |r|
      case column
      when :player
        r[:player].nickname.downcase
      when :cr, :ml
        r[column] || 0
      else
        r[column] || 0
      end
    end

    sort_direction == "desc" ? sorted.reverse : sorted
  end
end
