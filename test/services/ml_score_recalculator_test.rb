require "test_helper"

class MlScoreRecalculatorTest < ActiveSupport::TestCase
  test "a player with no games has no performance score" do
    unplayed = Player.create!(nickname: "NeverPlayed", battletag: "NeverPlayed#1", ml_score: 10.5)

    MlScoreRecalculator.new.call

    assert_nil unplayed.reload.ml_score,
      "sigmoid(0) is a dead-centre 50, and the shift would turn that into an " \
      "above-average PERF nobody earned - and exempt them from the new-player penalty"
  end

  test "a player with games still gets a score" do
    played = matches(:one).appearances.first.player

    MlScoreRecalculator.new.call

    assert_not_nil played.reload.ml_score
  end
end
