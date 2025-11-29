module LobbiesHelper
  def short_time_ago(time)
    return "-" unless time

    seconds = Time.current - time
    minutes = seconds / 60
    hours = minutes / 60
    days = hours / 24
    weeks = days / 7
    months = days / 30
    years = days / 365

    if seconds < 60
      "< 1m"
    elsif minutes < 60
      "#{minutes.round}m"
    elsif hours < 24
      "< 1d"
    elsif days < 7
      "#{days.round}d"
    elsif weeks < 4
      "#{weeks.round}w"
    elsif months < 12
      "#{months.round}mo"
    else
      "#{years.round}y"
    end
  end
end
