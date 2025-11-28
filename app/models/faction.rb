class Faction < ApplicationRecord
  COLORS = %w[red blue teal purple yellow green gray lightblue darkgreen brown].freeze
  NAMES = [ "Gondor", "Rohan", "Dol Amroth", "Fellowship", "Fangorn", "Isengard", "Easterlings", "Harad", "Minas Morgul", "Mordor" ].freeze

  COLOR_HEX = {
    "red" => "#ff0303",
    "blue" => "#0042ff",
    "teal" => "#1ce6b9",
    "purple" => "#540081",
    "yellow" => "#fffc00",
    "green" => "#20c000",
    "gray" => "#959697",
    "lightblue" => "#7ebff1",
    "darkgreen" => "#106246",
    "brown" => "#4e2a04"
  }.freeze

  # Base names for each faction (from game events)
  BASES = {
    "Gondor" => [ "Minas Tirith", "Lossnarch" ],
    "Rohan" => [ "Edoras", "Dunharrow" ],
    "Dol Amroth" => [ "Dol Amroth", "Calembel", "Lamedon" ],
    "Fellowship" => [],
    "Fangorn" => [ "Fangorn", "Skinbark", "Lorien" ],
    "Isengard" => [ "Orthanc", "Dunland" ],
    "Easterlings" => [ "Rhun", "Khand", "Dol Guldur" ],
    "Harad" => [ "Umbar", "Haradwaith", "Far Harad" ],
    "Minas Morgul" => [ "Minas Morgul" ],
    "Mordor" => [ "Barad-Dur", "Morannon" ]
  }.freeze

  # Reverse lookup: base name -> faction name
  BASE_TO_FACTION = BASES.flat_map { |faction, bases| bases.map { |base| [ base, faction ] } }.to_h.freeze

  # Ring-related events (not base deaths)
  RING_EVENTS = [ "Ring Drop", "Sauron gets the ring" ].freeze

  # Heroes for each faction (from game events)
  HEROES = {
    "Gondor" => [
      "Faramir son of Denethor", "Denethor son of Ecthelion", "Beregond son of Baranor",
      "Anborn", "Hirluin the Fair", "Denethor the Tainted"
    ],
    "Rohan" => [ "Théoden son of Thengel", "Eómer son of Eómund", "Eowyn", "Gamling", "Grimbold the Twisted" ],
    "Dol Amroth" => [ "Imrahil", "Forlong the Fat", "Duinhir", "Corinir" ],
    "Fellowship" => [
      "Gandalf the White", "Gandalf the Sorcerer", "Aragorn son of Arathorn", "King Elessar",
      "Boromir", "Frodo Baggins", "Samwise Gamgee", "Meriadoc Brandybuck", "Peregrin Took",
      "Legolas son of Thranduil", "Gimli son of Gloín"
    ],
    "Fangorn" => [ "Treebeard", "Galadriel", "Celeborn", "Haldir" ],
    "Isengard" => [ "Saruman of Many Colors", "Saruman the Terrible", "Grima Wormtongue", "Lurtz", "Úgluk", "Sharkû" ],
    "Easterlings" => [ "Ovatha IV", "Gwaer of Rhûn", "Kurgath the Terrible", "Zuldân" ],
    "Harad" => [
      "Suladân", "Carycyn of Far Harad", "Husâjek of Southern Harad", "Owynvan of the Corsairs"
    ],
    "Minas Morgul" => [
      "Er-Murâzor", "Adûnaphel the Quiet", "Akhôrahil the Blind Sorcerer",
      "Dwar of Waw", "Hoarmûrath of Dír", "Jí Indûr Dawndeath", "Ren the Unclean",
      "Khamûl the Easterling", "Ûvatha the Horseman"
    ],
    "Mordor" => [ "Sauron the Great", "Mouth of Sauron", "Gothmog", "Shagrat", "Bâdruík" ]
  }.freeze

  # Reverse lookup: hero name -> faction name
  HERO_TO_FACTION = HEROES.flat_map { |faction, heroes| heroes.map { |hero| [ hero, faction ] } }.to_h.freeze

  validates :name, presence: true, uniqueness: true
  validates :color, presence: true, inclusion: { in: COLORS }

  has_many :appearances

  def color_hex
    COLOR_HEX[color] || "#888888"
  end

  # Get bases for this faction
  def bases
    BASES[name] || []
  end

  # Find faction by base name
  def self.find_by_base(base_name)
    faction_name = BASE_TO_FACTION[base_name]
    find_by(name: faction_name) if faction_name
  end

  # Get heroes for this faction
  def heroes
    HEROES[name] || []
  end

  # Find faction by hero name
  def self.find_by_hero(hero_name)
    faction_name = HERO_TO_FACTION[hero_name]
    find_by(name: faction_name) if faction_name
  end
end
