class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Track page views with Ahoy (GDPR-friendly, no cookies)
  around_action :track_page_view_with_timing

  private

  def track_page_view_with_timing
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

    ahoy.track "Page View", request.path_parameters.merge(
      duration_ms: duration_ms,
      path: request.path,
      cached: response.headers["X-Cache-Hit"].present?
    )
  end

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.json { head :forbidden }
      format.html { redirect_to root_path, alert: exception.message }
    end
  end
end
