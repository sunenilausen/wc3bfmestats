require "test_helper"

class FactionEventStatsCalculatorTest < ActiveSupport::TestCase
  # Bases and heroes come from constants keyed by faction name, so the fixtures
  # already carry the real Orthanc/Dunland/Saruman set.
  setup do
    @isengard = factions(:isengard)
    @gondor = factions(:gondor)
  end

  # Builds one match whose replay carries the given events.
  def build_match(events:, good_victory:, map_version: "4.6", length: 3000, good_faction: nil, evil_faction: nil)
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: rand(1_000_000),
      body: {
        "length" => length,
        "data" => { "game" => { "map" => "Maps/BFME#{map_version}.w3x", "events" => events } }
      }
    )
    match = Match.create!(good_victory: good_victory, seconds: length, ignored: false,
                          wc3stats_replay: replay, map_version: map_version)
    match.appearances.create!(player: players(:one), faction: evil_faction || @isengard)
    match.appearances.create!(player: players(:two), faction: good_faction || @gondor)
    match
  end

  def ring_taken(time) = { "eventName" => "eventsTriggered", "args" => [ "Saruman takes the ring for himself" ], "time" => time }
  def hero_death(name, time) = { "eventName" => "heroDeath", "args" => [ name ], "time" => time }
  def base_death(name, time) = { "eventName" => "unitDeath", "args" => [ name ], "time" => time }

  def ring_stats(faction = @isengard)
    FactionEventStatsCalculator.new(faction).compute[:ring_event_stats]
  end

  test "Isengard's ring event is counted the same way Mordor's is" do
    build_match(events: [ ring_taken(600) ], good_victory: false)

    stats = ring_stats
    assert_equal "Saruman takes the ring for himself", stats[:name]
    assert_equal 1, stats[:occurrences]
    assert_equal 600, stats[:avg_time]
  end

  test "games from before the trigger existed are left out of the denominator" do
    build_match(events: [ ring_taken(600) ], good_victory: false, map_version: "4.6")
    build_match(events: [], good_victory: false, map_version: "4.5e")

    stats = ring_stats
    assert_equal 1, stats[:total_games],
      "the 4.5e game could not have fired the trigger, so counting it would understate the rate"
    assert_equal 100.0, stats[:occurrence_rate]
    assert_equal "4.6", stats[:min_version]
  end

  test "Saruman dying in his ring form is counted, and only after he takes it" do
    build_match(events: [ ring_taken(600), hero_death("Saruman the Terrible", 900) ], good_victory: false)
    build_match(events: [ hero_death("Saruman the Terrible", 400), ring_taken(600) ], good_victory: false)

    stats = ring_stats
    assert_equal 2, stats[:occurrences]
    assert_equal 1, stats[:ring_hero_deaths], "a death before the ring was taken is not a consequence of it"
    assert_equal 300, stats[:ring_hero_avg_time_to_death]
    assert_equal "Saruman", stats[:ring_hero_name]
  end

  test "the row names the bases, like the hero row names the hero" do
    build_match(events: [ ring_taken(600), base_death("Orthanc", 800), base_death("Dunland", 900) ],
                good_victory: false)

    assert_equal "Orthanc and Dunland dies", ring_stats[:no_bases_label]
  end

  test "being left with no bases at all is counted, one base is not" do
    build_match(events: [ ring_taken(600), base_death("Orthanc", 1200), base_death("Dunland", 800) ],
                good_victory: false)
    build_match(events: [ ring_taken(600), base_death("Dunland", 900) ], good_victory: false)

    stats = ring_stats
    assert_equal 1, stats[:no_bases_count], "losing only Dunland does not leave them solo"
    assert_equal 50.0, stats[:no_bases_rate]
    assert_equal 600, stats[:no_bases_avg_time], "timed from the ring to the second base falling"
  end

  test "a base lost before the ring still leaves them with no bases" do
    build_match(events: [ base_death("Orthanc", 300), ring_taken(600), base_death("Dunland", 900) ],
                good_victory: false)

    assert_equal 1, ring_stats[:no_bases_count],
      "what matters is ending up with nothing, not whether the ring caused it"
  end

  test "only Isengard reports what happened to its bases" do
    build_match(events: [ ring_taken(600), base_death("Orthanc", 1200) ], good_victory: false)

    mordor = factions(:mordor)
    build_match(events: [ { "eventName" => "eventsTriggered", "args" => [ "Sauron gets the ring" ], "time" => 600 },
                          base_death("Barad-Dur", 1200) ],
                good_victory: false, evil_faction: mordor)

    assert_not_nil ring_stats[:no_bases_rate], "Isengard reports whether it was left with no bases"

    mordor_stats = ring_stats(mordor)
    assert_equal 1, mordor_stats[:occurrences], "the Mordor game was counted, it just reports no base row"
    assert_nil mordor_stats[:no_bases_rate], "Mordor's base rows were deliberately left out"
  end

  test "taking the ring and still losing is counted" do
    build_match(events: [ ring_taken(600) ], good_victory: true)   # evil lost
    build_match(events: [ ring_taken(600) ], good_victory: false)  # evil won

    stats = ring_stats
    assert_equal "Evil loses", stats[:loss_label]
    assert_equal 1, stats[:losses]
    assert_equal 50.0, stats[:loss_rate]
  end

  test "a good faction's ring event is labelled from its own side" do
    fellowship = factions(:fellowship)
    build_match(events: [ { "eventName" => "eventsTriggered", "args" => [ "Ring Drop" ], "time" => 600 } ],
                good_victory: false, good_faction: fellowship)

    assert_equal "Good loses", ring_stats(fellowship)[:loss_label]
  end

  # --- pre-4.6, where the trigger did not exist yet -----------------------

  test "before the trigger existed, the ring form dying is what we count" do
    build_match(events: [ hero_death("Saruman the Terrible", 900) ], good_victory: false, map_version: "4.5e")
    build_match(events: [], good_victory: false, map_version: "4.5e")

    legacy = FactionEventStatsCalculator.new(@isengard).compute[:legacy_ring_stats]
    assert_equal "Saruman the Terrible", legacy[:hero_name]
    assert_equal "4.6", legacy[:before_version]
    assert_equal 2, legacy[:total_games]
    assert_equal 1, legacy[:deaths]
    assert_equal 50.0, legacy[:death_rate]
    assert_equal 900, legacy[:avg_time]
  end

  test "the bases row is measured against the games he died in, not all games" do
    build_match(events: [ hero_death("Saruman the Terrible", 900),
                          base_death("Orthanc", 1000), base_death("Dunland", 1100) ],
                good_victory: false, map_version: "4.5e")
    build_match(events: [ hero_death("Saruman the Terrible", 900), base_death("Orthanc", 1000) ],
                good_victory: true, map_version: "4.5e")

    legacy = FactionEventStatsCalculator.new(@isengard).compute[:legacy_ring_stats]
    assert_equal "Orthanc and Dunland dies", legacy[:bases_label]
    assert_equal 1, legacy[:bases_count], "one base surviving is not both dying"
    assert_equal 50.0, legacy[:bases_rate]
    assert_equal 1, legacy[:losses]
    assert_equal 50.0, legacy[:loss_rate]
  end

  test "4.6+ games are left out of the pre-4.6 section entirely" do
    build_match(events: [ hero_death("Saruman the Terrible", 900) ], good_victory: false, map_version: "4.6")

    assert_nil FactionEventStatsCalculator.new(@isengard).compute[:legacy_ring_stats],
      "once the trigger exists we read the trigger, not the death"
  end

  test "a faction whose trigger always existed has no pre-4.6 section" do
    build_match(events: [ { "eventName" => "eventsTriggered", "args" => [ "Sauron gets the ring" ], "time" => 600 },
                          hero_death("Sauron the Great", 900) ],
                good_victory: false, map_version: "4.5e", evil_faction: factions(:mordor))

    assert_nil FactionEventStatsCalculator.new(factions(:mordor)).compute[:legacy_ring_stats]
  end

  test "a faction's own ring trigger is not repeated as a ringbearer event" do
    build_match(events: [ ring_taken(600) ], good_victory: false)

    stats = FactionEventStatsCalculator.new(@isengard).compute
    assert_equal 1, stats[:ring_event_stats][:occurrences]
    assert_nil stats[:ringbearer_stats],
      "Saruman taking the ring is Isengard's ring event - repeating it as a ringbearer event says nothing new"
  end

  test "other factions still get their ringbearer events" do
    build_match(events: [ { "eventName" => "eventsTriggered", "args" => [ "Denethor uses the ring" ], "time" => 600 } ],
                good_victory: false, good_faction: factions(:gondor))

    stats = FactionEventStatsCalculator.new(factions(:gondor)).compute[:ringbearer_stats]
    assert_equal 1, stats[:occurrences]
    assert_equal({ "Denethor" => 1 }, stats[:heroes])
  end

  test "a rare ring event lists the games behind it" do
    match = build_match(events: [ ring_taken(600) ], good_victory: false)

    listed = ring_stats[:matches]
    assert_equal 1, listed.size
    assert_equal match.id, listed.first[:id]
    assert_equal match.to_param, listed.first[:param]
    assert_equal 600, listed.first[:event_time]
    assert listed.first[:won], "Isengard is evil, so a Good defeat is their win"
  end

  test "a common ring event lists nothing - the percentage is the point" do
    stub_const = FactionEventStatsCalculator::RING_MATCH_LIST_MAX
    FactionEventStatsCalculator.send(:remove_const, :RING_MATCH_LIST_MAX)
    FactionEventStatsCalculator.const_set(:RING_MATCH_LIST_MAX, 1)

    build_match(events: [ ring_taken(600) ], good_victory: false)
    build_match(events: [ ring_taken(700) ], good_victory: false)

    assert_nil ring_stats[:matches], "too many games to be worth reading one by one"
  ensure
    FactionEventStatsCalculator.send(:remove_const, :RING_MATCH_LIST_MAX)
    FactionEventStatsCalculator.const_set(:RING_MATCH_LIST_MAX, stub_const)
  end

  test "a faction with no ring event has no ring stats" do
    build_match(events: [ ring_taken(600) ], good_victory: false)

    assert_nil ring_stats(factions(:rohan))
  end
end
