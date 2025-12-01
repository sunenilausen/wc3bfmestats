namespace :cache do
  desc "Invalidate stats cache"
  task invalidate: :environment do
    StatsCacheKey.invalidate!
    puts "Stats cache invalidated"
  end
end
