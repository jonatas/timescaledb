module Timescaledb
  class Database
    module Quoting
      # Quotes given value and escapes single quote and backslash characters.
      #
      # @return [String] The given value between quotes
      def quote(value)
        "'#{value.gsub("\\", '\&\&').gsub("'", "''")}'"
      end
    end
  end
end
