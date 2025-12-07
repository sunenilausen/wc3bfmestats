# frozen_string_literal: true

module Admin
  class AnalyticsController < BaseController
    before_action :authorize_admin

    def index
      @period = params[:period] || "7days"
      @start_date = period_start_date(@period)

      @total_visits = Ahoy::Visit.where("started_at >= ?", @start_date).count
      @total_page_views = Ahoy::Event.where(name: "Page View").where("time >= ?", @start_date).count

      @visits_by_day = Ahoy::Visit
        .where("started_at >= ?", @start_date)
        .group_by_day(:started_at)
        .count

      @page_views_by_day = Ahoy::Event
        .where(name: "Page View")
        .where("time >= ?", @start_date)
        .group_by_day(:time)
        .count

      @top_pages = top_pages(@start_date, 20)
      @top_players = top_players(@start_date, 10)
      @top_browsers = Ahoy::Visit.where("started_at >= ?", @start_date).group(:browser).order("count_all DESC").limit(10).count
      @top_devices = Ahoy::Visit.where("started_at >= ?", @start_date).group(:device_type).order("count_all DESC").limit(10).count
      @top_referrers = Ahoy::Visit.where("started_at >= ?", @start_date).where.not(referring_domain: [ nil, "" ]).group(:referring_domain).order("count_all DESC").limit(10).count
    end

    private

    def authorize_admin
      authorize! :manage, :analytics
    end

    def period_start_date(period)
      case period
      when "today"
        Time.current.beginning_of_day
      when "yesterday"
        1.day.ago.beginning_of_day
      when "7days"
        7.days.ago.beginning_of_day
      when "30days"
        30.days.ago.beginning_of_day
      when "90days"
        90.days.ago.beginning_of_day
      when "year"
        1.year.ago.beginning_of_day
      when "all"
        Time.at(0)
      else
        7.days.ago.beginning_of_day
      end
    end

    def top_pages(start_date, limit)
      events = Ahoy::Event
        .where(name: "Page View")
        .where("time >= ?", start_date)

      page_counts = Hash.new(0)

      events.find_each do |event|
        props = event.properties
        controller = props["controller"]
        action = props["action"]
        id = props["id"]

        page_name = build_page_name(controller, action, id)
        page_counts[page_name] += 1
      end

      page_counts.sort_by { |_, count| -count }.first(limit).to_h
    end

    def build_page_name(controller, action, id)
      return "Unknown" if controller.blank?

      base = "#{controller}##{action}"
      id.present? ? "#{base} (#{id})" : base
    end

    def top_players(start_date, limit)
      events = Ahoy::Event
        .where(name: "Page View")
        .where("time >= ?", start_date)

      player_counts = Hash.new(0)

      events.find_each do |event|
        props = event.properties
        next unless props["controller"] == "players" && props["action"] == "show"

        player_id = props["id"]
        player_counts[player_id] += 1 if player_id.present?
      end

      player_ids = player_counts.sort_by { |_, count| -count }.first(limit).to_h.keys
      players = Player.where(id: player_ids).index_by(&:id)

      player_counts.sort_by { |_, count| -count }.first(limit).map do |player_id, count|
        player = players[player_id.to_i]
        [ player, count ] if player
      end.compact.to_h
    end
  end
end
