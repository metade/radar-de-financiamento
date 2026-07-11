require "date"

module FundingRadar
  Opportunity = Data.define(
    :id,
    :title,
    :programme,
    :opening_date,
    :deadline,
    :funding_amount,
    :funding_source,
    :official_link,
    :eligible_applicants,
    :partnership_requirements,
    :other_requirements,
    :summary,
    :themes
  ) do
    def self.from_hash(hash)
      data = hash.transform_keys(&:to_sym)

      new(
        id: data.fetch(:id),
        title: data.fetch(:title),
        programme: data.fetch(:programme),
        opening_date: data[:opening_date],
        deadline: data[:deadline],
        funding_amount: data[:funding_amount].to_s,
        funding_source: data.fetch(:funding_source),
        official_link: data.fetch(:official_link),
        eligible_applicants: Array(data[:eligible_applicants]),
        partnership_requirements: data[:partnership_requirements].to_s,
        other_requirements: data[:other_requirements].to_s,
        summary: data.fetch(:summary),
        themes: Array(data[:themes]).map(&:to_s)
      )
    end

    def duplicate_key
      return official_link.to_s.strip.downcase unless official_link.to_s.strip.empty?

      "#{programme}-#{title}".downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    def deadline_date
      return nil if deadline.to_s.strip.empty?

      Date.iso8601(deadline.to_s)
    rescue Date::Error
      nil
    end

    def opening_date_value
      return nil if opening_date.to_s.strip.empty?

      Date.iso8601(opening_date.to_s)
    rescue Date::Error
      nil
    end
  end
end
