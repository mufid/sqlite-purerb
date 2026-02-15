# frozen_string_literal: true

module SqlitePurerb
  # Token represents a lexical token from SQL input
  # Matches the Token struct in SQLite's parse.y
  Token = Struct.new(:type, :value, :start, :length) do
    def to_s
      value.to_s
    end
  end
end
