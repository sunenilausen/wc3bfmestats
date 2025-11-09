# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end


Faction.find_or_create_by!(name: "Gondor", color: "red", good: true)
Faction.find_or_create_by!(name: "Rohan", color: "blue", good: true)
Faction.find_or_create_by!(name: "Dol Amroth", color: "teal", good: true)
Faction.find_or_create_by!(name: "Fellowship", color: "purple", good: true)
Faction.find_or_create_by!(name: "Fangorn", color: "yellow", good: true)
Faction.find_or_create_by!(name: "Isengard", color: "green", good: false)
Faction.find_or_create_by!(name: "Easterlings", color: "gray", good: false)
Faction.find_or_create_by!(name: "Harad", color: "lightblue", good: false)
Faction.find_or_create_by!(name: "Nazgul", color: "darkgreen", good: false)
Faction.find_or_create_by!(name: "Mordor", color: "brown", good: false)
