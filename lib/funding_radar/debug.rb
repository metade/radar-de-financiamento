module FundingRadar
  module Debug
    module_function

    def enabled?
      ENV["FUNDING_RADAR_DEBUG"] == "true"
    end

    def log(message)
      warn "[funding-radar] #{message}" if enabled?
    end

    def timed(label)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      log "#{label}..."
      result = yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      log format("#{label} done (%.2fs)", elapsed)
      result
    rescue StandardError => error
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      log format("#{label} failed after %.2fs: %s: %s", elapsed, error.class, error.message)
      raise
    end
  end
end
