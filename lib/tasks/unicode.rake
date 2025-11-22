namespace :unicode do
  desc "Preview Korean/Unicode name fixes without applying"
  task preview: :environment do
    puts "=" * 60
    puts "Unicode Name Fixer - Preview"
    puts "=" * 60
    puts

    fixer = UnicodeNameFixer.new
    players_to_fix = fixer.preview

    if players_to_fix.empty?
      puts "No players with encoding issues found."
      next
    end

    puts "Found #{players_to_fix.count} players with encoding issues:"
    puts

    players_to_fix.each do |player|
      puts "Player ##{player[:id]}:"
      if player[:nickname][:from] != player[:nickname][:to]
        puts "  Nickname: #{player[:nickname][:from]} → #{player[:nickname][:to]}"
      end
      if player[:battletag][:from] != player[:battletag][:to]
        puts "  Battletag: #{player[:battletag][:from]} → #{player[:battletag][:to]}"
      end
      puts
    end

    puts "Run 'rails unicode:fix' to apply these changes."
    puts "=" * 60
  end

  desc "Fix Korean/Unicode encoding issues in player names"
  task fix: :environment do
    puts "=" * 60
    puts "Unicode Name Fixer"
    puts "=" * 60
    puts

    fixer = UnicodeNameFixer.new
    preview = fixer.preview

    if preview.empty?
      puts "No players with encoding issues found."
      next
    end

    puts "Found #{preview.count} players with encoding issues."
    puts

    print "Apply fixes? (y/N): "
    confirmation = $stdin.gets&.strip&.downcase

    unless confirmation == "y"
      puts "Aborted."
      next
    end

    puts
    puts "Fixing encoding issues..."
    puts

    fixer.call

    puts "=" * 60
    puts "Summary"
    puts "=" * 60
    puts "Players fixed: #{fixer.fixed_count}"

    if fixer.errors.any?
      puts
      puts "Errors (#{fixer.errors.count}):"
      fixer.errors.each { |e| puts "  - #{e}" }
    end

    if fixer.changes.any?
      puts
      puts "Changes made:"
      fixer.changes.select { |c| c[:type] == :player }.each do |change|
        puts "  Player ##{change[:id]}:"
        puts "    #{change[:nickname][:from]} → #{change[:nickname][:to]}"
      end
    end

    puts "=" * 60
  end

  desc "Fix Korean/Unicode encoding issues without confirmation"
  task fix_force: :environment do
    puts "=" * 60
    puts "Unicode Name Fixer (Force Mode)"
    puts "=" * 60
    puts

    fixer = UnicodeNameFixer.new
    fixer.call

    puts "Players fixed: #{fixer.fixed_count}"

    if fixer.errors.any?
      puts "Errors: #{fixer.errors.count}"
      fixer.errors.first(5).each { |e| puts "  - #{e}" }
    end

    puts "=" * 60
  end
end
