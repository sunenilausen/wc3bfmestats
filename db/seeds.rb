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
Faction.find_or_create_by!(name: "Minas Morgul", color: "darkgreen", good: false)
Faction.find_or_create_by!(name: "Mordor", color: "brown", good: false)

Player.find_or_create_by!(nickname: "KaptajnSnaps", battletag: "KaptajnSnaps#1987", region: "eu", elo_rating_seed: 1500.0, elo_rating: 1500.0, battlenet_number: "1987", battlenet_name: "KaptajnSnaps")

Player.find_or_create_by!(nickname: "Gandalf", battletag: "Gandalf#1122", region: "eu", elo_rating_seed: 1650.0, elo_rating: 1650.0, battlenet_number: "1122", battlenet_name: "Gandalf")
Player.find_or_create_by!(nickname: "Aragorn", battletag: "Aragorn#1234", region: "eu", elo_rating_seed: 1600.0, elo_rating: 1600.0, battlenet_number: "1234", battlenet_name: "Aragorn")
Player.find_or_create_by!(nickname: "Legolas", battletag: "Legolas#5678", region: "eu", elo_rating_seed: 1580.0, elo_rating: 1580.0, battlenet_number: "5678", battlenet_name: "Legolas")
Player.find_or_create_by!(nickname: "Gimli", battletag: "Gimli#4321", region: "eu", elo_rating_seed: 1550.0, elo_rating: 1550.0, battlenet_number: "4321", battlenet_name: "Gimli")
Player.find_or_create_by!(nickname: "Boromir", battletag: "Boromir#8765", region: "eu", elo_rating_seed: 1530.0, elo_rating: 1530.0, battlenet_number: "8765", battlenet_name: "Boromir")
Player.find_or_create_by!(nickname: "Frodo", battletag: "Frodo#2468", region: "eu", elo_rating_seed: 1510.0, elo_rating: 1510.0, battlenet_number: "2468", battlenet_name: "Frodo")
Player.find_or_create_by!(nickname: "Samwise", battletag: "Samwise#1357", region: "eu", elo_rating_seed: 1490.0, elo_rating: 1490.0, battlenet_number: "1357", battlenet_name: "Samwise")
Player.find_or_create_by!(nickname: "Merry", battletag: "Merry#9753", region: "eu", elo_rating_seed: 1470.0, elo_rating: 1470.0, battlenet_number: "9753", battlenet_name: "Merry")
Player.find_or_create_by!(nickname: "Pippin", battletag: "Pippin#8642", region: "eu", elo_rating_seed: 1450.0, elo_rating: 1450.0, battlenet_number: "8642", battlenet_name: "Pippin")
