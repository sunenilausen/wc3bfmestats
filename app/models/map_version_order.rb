# Ranks map versions in release order, so matches can be sorted by which
# version of the map they were played on rather than by a timestamp.
#
# Why this exists: 43% of replays carry no filename we can parse a game time
# out of, so their played_at falls back to the upload time. When someone bulk
# uploads a pile of old replays, every one of them lands on today's date and a
# 4.4e game sorts in among the 4.7RC2 games. The map version, on the other
# hand, is read straight off the replay and cannot drift.
#
# The rank is a pure function of the version string - no database lookups, no
# dense index that shifts when a new version appears - so a match can be
# ranked the moment it is built and never needs revisiting.
#
# Ordering rules, in order of significance:
#
#   4.5   < 4.6                major, then minor
#   4.5   < 4.5b < 4.5c        the plain release precedes its lettered patches
#   4.7RC < 4.7RC2 < 4.7       pre-releases (Beta/RC/Test) precede the release
#   4.4   = 4.4Obs             "Obs" is the same version with observer slots
#   4.0l  = 4.0L               letters are case-insensitive
#
module MapVersionOrder
  # Wide enough that a version's own rank can never collide with the next
  # letter's, and that a pre-release always sorts below its release.
  RELEASE = 10_000
  LETTER_SPAN = 100_000
  LETTERS = 27

  # Beta < RC < Test only matters if a version ever ships two kinds of
  # pre-release; alphabetical is as good a guess as any.
  PRERELEASE_KINDS = %w[beta rc test].freeze

  # BFME4.5e -> "4.5e", with optional pre-release qualifier and the "~1"
  # suffix Windows adds to a duplicate download.
  PATTERN = /\A(\d+)\.(\d+)([a-z])?(?:(beta|rc|test)(\d*))?(?:~\d+)?\z/i

  module_function

  # Returns an integer for a parseable version, nil otherwise. Sorting by it
  # puts versions in release order.
  def rank(map_version)
    return nil if map_version.blank?

    # "Obs" builds are the same version handed out with observer slots open,
    # and were played alongside it - rank them as the version itself.
    normalized = map_version.to_s.strip.sub(/obs\z/i, "")
    parts = normalized.match(PATTERN)
    return nil unless parts

    major, minor, letter, kind, number = parts.captures
    letter_index = letter ? letter.downcase.ord - "a".ord + 1 : 0

    tail = if kind
      PRERELEASE_KINDS.index(kind.downcase).to_i * 1_000 + number.to_i
    else
      RELEASE
    end

    ((major.to_i * 100 + minor.to_i) * LETTERS + letter_index) * LETTER_SPAN + tail
  end

  # The rank to store on a match. A replay we cannot read a version off (the
  # one .w3m map, say) borrows the rank of whichever version was current when
  # it was played, so it interleaves by date instead of piling up at one end.
  def rank_for(map_version, played_at: nil)
    rank(map_version) || rank_at(played_at)
  end

  def rank_at(played_at)
    return nil if played_at.blank?

    Match.where.not(map_version_order: nil)
      .where(played_at: ..played_at)
      .maximum(:map_version_order)
  end
end
