# frozen_string_literal: true

class RatingRecalculationJob < ApplicationJob
  queue_as :default

  # Cancel any pending rating recalculation jobs before enqueuing a new one
  def self.enqueue_and_cancel_pending
    cancel_pending_jobs
    perform_later
  end

  def perform
    Rails.logger.info "RatingRecalculationJob: Starting full rating recalculation"

    CustomRatingRecalculator.new.call

    Rails.logger.info "RatingRecalculationJob: Recalculating ML scores"
    MlScoreRecalculator.new.call

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
