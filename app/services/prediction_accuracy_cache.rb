# Caches prediction accuracy by confidence bucket for display on lobby pages
# Uses the same calculation as HomeController but with caching
class PredictionAccuracyCache
  CACHE_KEY = "prediction_accuracy_by_bucket"

  # Returns accuracy data for all buckets
  # { "50-55" => { accuracy: 52.3, total: 45 }, "55-60" => { accuracy: 58.1, total: 38 }, ... }
  def self.all
    Rails.cache.fetch([ CACHE_KEY, StatsCacheKey.key ]) do
      calculate_accuracy_by_bucket
    end
  end

  # Returns accuracy for a specific confidence percentage
  # e.g., confidence_pct = 67.5 would return accuracy for "65-70" bucket
  def self.accuracy_for(confidence_pct)
    return nil if confidence_pct.nil?

    bucket_key = bucket_for_confidence(confidence_pct)
    data = all[bucket_key]
    return nil unless data && data[:total] > 0

    {
      accuracy: data[:accuracy],
      total: data[:total],
      bucket: bucket_key
    }
  end

  # Manually invalidate the cache
  def self.invalidate!
    Rails.cache.delete_matched("#{CACHE_KEY}*")
  end

  private

  def self.calculate_accuracy_by_bucket
    matches = Match.includes(appearances: :faction)
                   .where(ignored: false)
                   .where.not(good_victory: nil)
                   .where.not(predicted_good_win_pct: nil)

    # Buckets in 5% increments from 50% to 100%
    buckets = {}
    (50..95).step(5).each do |start|
      label = "#{start}-#{start + 5}"
      buckets[label] = { correct: 0, total: 0 }
    end

    matches.find_each do |match|
      good_pct = match.predicted_good_win_pct.to_f
      confidence_pct = [ good_pct, 100 - good_pct ].max
      good_favored = good_pct >= 50
      prediction_correct = (good_favored && match.good_victory) || (!good_favored && !match.good_victory)

      bucket_key = bucket_for_confidence(confidence_pct)
      buckets[bucket_key][:total] += 1
      buckets[bucket_key][:correct] += 1 if prediction_correct
    end

    # Convert to final format with percentages
    buckets.transform_values do |data|
      {
        accuracy: data[:total] > 0 ? (data[:correct].to_f / data[:total] * 100).round(1) : nil,
        total: data[:total]
      }
    end
  end

  def self.bucket_for_confidence(pct)
    bucket_start = ((pct.to_i / 5) * 5).clamp(50, 95)
    "#{bucket_start}-#{bucket_start + 5}"
  end
end
