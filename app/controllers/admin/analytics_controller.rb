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

      @unique_visitors_by_day = Ahoy::Visit
        .where("started_at >= ?", @start_date)
        .group_by_day(:started_at)
        .distinct
        .count(:visitor_token)

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

      # Page load time analytics
      @page_load_stats = compute_page_load_stats(@start_date)
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

      page_visits = Hash.new(0)
      page_unique_visits = Hash.new { |h, k| h[k] = Set.new }

      events.find_each do |event|
        props = event.properties
        controller = props["controller"]
        action = props["action"]
        id = props["id"]

        page_name = build_page_name(controller, action, id)
        page_visits[page_name] += 1
        page_unique_visits[page_name] << event.visit_id
      end

      page_visits.sort_by { |_, count| -count }.first(limit).map do |page_name, visits|
        [ page_name, { visits: visits, unique_visits: page_unique_visits[page_name].size } ]
      end.to_h
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

      player_visits = Hash.new(0)
      player_unique_visits = Hash.new { |h, k| h[k] = Set.new }

      events.find_each do |event|
        props = event.properties
        next unless props["controller"] == "players" && props["action"] == "show"

        player_identifier = props["id"]
        next if player_identifier.blank?

        player_visits[player_identifier] += 1
        player_unique_visits[player_identifier] << event.visit_id
      end

      # Get top identifiers and look up players by battletag or id
      top_identifiers = player_visits.sort_by { |_, count| -count }.first(limit).to_h

      top_identifiers.filter_map do |identifier, visits|
        player = Player.find_by_battletag_or_id(identifier)
        next unless player

        unique_visits = player_unique_visits[identifier].size
        [ player, { visits: visits, unique_visits: unique_visits } ]
      end.to_h
    end

    def compute_page_load_stats(start_date)
      events = Ahoy::Event
        .where(name: "Page View")
        .where("time >= ?", start_date)

      durations = []
      page_durations = Hash.new { |h, k| h[k] = [] }

      events.find_each do |event|
        props = event.properties
        duration = props["duration_ms"]
        next unless duration.is_a?(Numeric) && duration > 0

        durations << duration

        controller = props["controller"]
        action = props["action"]
        page_name = controller.present? ? "#{controller}##{action}" : "unknown"
        page_durations[page_name] << duration
      end

      return nil if durations.empty?

      sorted = durations.sort
      count = sorted.size

      # Overall stats
      overall = {
        count: count,
        avg: (sorted.sum / count.to_f).round(1),
        median: percentile(sorted, 50),
        p95: percentile(sorted, 95),
        min: sorted.first.round(1),
        max: sorted.last.round(1)
      }

      # Per-page stats (top 10 slowest by average)
      per_page = page_durations.map do |page, times|
        sorted_times = times.sort
        {
          page: page,
          count: times.size,
          avg: (sorted_times.sum / times.size.to_f).round(1),
          median: percentile(sorted_times, 50),
          p95: percentile(sorted_times, 95)
        }
      end.sort_by { |s| -s[:avg] }.first(10)

      { overall: overall, per_page: per_page }
    end

    def percentile(sorted_array, pct)
      return nil if sorted_array.empty?
      index = (pct / 100.0 * (sorted_array.size - 1)).round
      sorted_array[index].round(1)
    end
  end
end
