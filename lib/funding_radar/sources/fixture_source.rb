require "yaml"

module FundingRadar
  module Sources
    class FixtureSource
      def initialize(path:)
        @path = path
      end

      def fetch
        YAML.safe_load_file(@path, permitted_classes: [Date], aliases: false).fetch("opportunities").map do |row|
          Opportunity.from_hash(row)
        end
      end
    end
  end
end
