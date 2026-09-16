require_relative "../lib/funding_radar/static_api"

Jekyll::Hooks.register :site, :post_write do |site|
  reports = site.collections.fetch("reports").docs
  FundingRadar::StaticApi::Builder.new(reports: reports).write(site.dest)
end
