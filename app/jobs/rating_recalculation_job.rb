# frozen_string_literal: true

class RatingRecalculationJob < ApplicationJob
  queue_as :default

  # Cancel any pending rating recalculation jobs before enqueuing a new one
  # @param match_id [Integer, nil] Optional match ID to prebuild cache for after recalculation
  def self.enqueue_and_cancel_pending(match_id = nil)
    cancel_pending_jobs
    perform_later(match_id)
  end

  def perform(match_id = nil)
    Rails.logger.info "RatingRecalculationJob: Starting full rating recalculation"

    Rails.logger.info "RatingRecalculationJob: Backfilling APM data"
    apm = ApmBackfiller.new
    apm.call
    Rails.logger.info "RatingRecalculationJob: Updated #{apm.updated_count} appearances with APM"

    CustomRatingRecalculator.new.call

    Rails.logger.info "RatingRecalculationJob: Recalculating ML scores"
    MlScoreRecalculator.new.call

    Rails.logger.info "RatingRecalculationJob: Recalculating stay/leave percentages"
    StayLeaveRecalculator.new.call

    # Prebuild caches for the affected match and participants
    if match_id
      Rails.logger.info "RatingRecalculationJob: Prebuilding caches for match ##{match_id}"
      CachePrebuildJob.perform_later(match_id)
    else
      # If no specific match, prebuild for the most recent match
      recent_match = Match.where(ignored: false).order(updated_at: :desc).first
      if recent_match
        Rails.logger.info "RatingRecalculationJob: Prebuilding caches for most recent match ##{recent_match.id}"
        CachePrebuildJob.perform_later(recent_match.id)
      end
    end

    Rails.logger.info "RatingRecalculationJob: Completed"
  end

  # Cancel all pending RatingRecalculationJob jobs
  def self.cancel_pending_jobs
    # For Solid Queue, we can delete pending jobs from the queue
    return unless defined?(SolidQueue::Job)

    pending_jobs = SolidQueue::Job
      .where(class_name: "RatingRecalculationJob")
      .where(finished_at: nil)

    count = pending_jobs.count
    if count > 0
      pending_jobs.destroy_all
      Rails.logger.info "RatingRecalculationJob: Cancelled #{count} pending job(s)"
    end
  rescue ActiveRecord::StatementInvalid
    # Table doesn't exist (e.g., in test environment)
    nil
  end
end
