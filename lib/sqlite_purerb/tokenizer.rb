# frozen_string_literal: true

module SqlitePurerb
  # Tokenizer for SQL input
  # Generates tokens compatible with the Parserb parser
  class Tokenizer
    KEYWORDS = {
      'SELECT' => Sqlite3Parser::TK::SELECT,
      'FROM' => Sqlite3Parser::TK::FROM,
      'WHERE' => Sqlite3Parser::TK::WHERE,
      'AND' => Sqlite3Parser::TK::AND_,
      'OR' => Sqlite3Parser::TK::OR_,
      'AS' => Sqlite3Parser::TK::AS,
      'NOT' => Sqlite3Parser::TK::NOT_,
      'NULL' => Sqlite3Parser::TK::NULL,
      'IS' => Sqlite3Parser::TK::IS,
      'IN' => Sqlite3Parser::TK::IN_,
      'LIKE' => Sqlite3Parser::TK::LIKE_KW,
      'BETWEEN' => Sqlite3Parser::TK::BETWEEN,
      'ORDER' => Sqlite3Parser::TK::ORDER,
      'BY' => Sqlite3Parser::TK::BY,
      'GROUP' => Sqlite3Parser::TK::GROUP,
      'HAVING' => Sqlite3Parser::TK::HAVING,
      'LIMIT' => Sqlite3Parser::TK::LIMIT,
      'OFFSET' => Sqlite3Parser::TK::OFFSET,
      'DISTINCT' => Sqlite3Parser::TK::DISTINCT,
      'ALL' => Sqlite3Parser::TK::ALL,
      'JOIN' => Sqlite3Parser::TK::JOIN,
      'LEFT' => Sqlite3Parser::TK::JOIN_KW,
      'RIGHT' => Sqlite3Parser::TK::JOIN_KW,
      'INNER' => Sqlite3Parser::TK::JOIN_KW,
      'OUTER' => Sqlite3Parser::TK::JOIN_KW,
      'CROSS' => Sqlite3Parser::TK::JOIN_KW,
      'NATURAL' => Sqlite3Parser::TK::JOIN_KW,
      'ON' => Sqlite3Parser::TK::ON,
      'USING' => Sqlite3Parser::TK::USING
    }.freeze

    def initialize(sql)
      @sql = sql
      @pos = 0
    end

    def tokenize
      tokens = []

      while @pos < @sql.length
        # Skip whitespace
        if @sql[@pos] =~ /\s/
          @pos += 1
          next
        end

        token = read_token
        tokens << token if token
      end

      # Grammar requires semicolon at end - add if not present
      if tokens.empty? || tokens.last.type != Sqlite3Parser::TK::SEMI
        tokens << Token.new(Sqlite3Parser::TK::SEMI, ';', @pos, 0)
      end

      tokens << Token.new(Sqlite3Parser::TK::EOF, nil, @pos, 0)
      tokens
    end

    private

    def read_token
      start = @pos

      # Keywords and identifiers
      if @sql[@pos] =~ /[a-zA-Z_]/
        @pos += 1 while @pos < @sql.length && @sql[@pos] =~ /[a-zA-Z0-9_]/
        word = @sql[start...@pos]
        type = KEYWORDS[word.upcase] || Sqlite3Parser::TK::ID
        return Token.new(type, word, start, @pos - start)
      end

      # Numbers
      if @sql[@pos] =~ /[0-9]/
        @pos += 1 while @pos < @sql.length && @sql[@pos] =~ /[0-9.]/
        value = @sql[start...@pos]
        return Token.new(Sqlite3Parser::TK::INTEGER, value, start, @pos - start)
      end

      # Strings (single quoted)
      if @sql[@pos] == "'"
        @pos += 1
        str_start = @pos
        while @pos < @sql.length && @sql[@pos] != "'"
          @pos += 1
        end
        value = @sql[str_start...@pos]
        @pos += 1 # skip closing quote
        return Token.new(Sqlite3Parser::TK::STRING, value, start, @pos - start)
      end

      # Two-character operators
      case @sql[@pos, 2]
      when '!='
        @pos += 2
        return Token.new(Sqlite3Parser::TK::NE, '!=', start, 2)
      when '<>'
        @pos += 2
        return Token.new(Sqlite3Parser::TK::NE, '<>', start, 2)
      when '<='
        @pos += 2
        return Token.new(Sqlite3Parser::TK::LE, '<=', start, 2)
      when '>='
        @pos += 2
        return Token.new(Sqlite3Parser::TK::GE, '>=', start, 2)
      end

      # Single-character operators
      case @sql[@pos]
      when '*'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::STAR, '*', start, 1)
      when ','
        @pos += 1
        return Token.new(Sqlite3Parser::TK::COMMA, ',', start, 1)
      when '('
        @pos += 1
        return Token.new(Sqlite3Parser::TK::LP, '(', start, 1)
      when ')'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::RP, ')', start, 1)
      when '='
        @pos += 1
        return Token.new(Sqlite3Parser::TK::EQ, '=', start, 1)
      when '<'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::LT, '<', start, 1)
      when '>'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::GT, '>', start, 1)
      when ';'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::SEMI, ';', start, 1)
      when '.'
        @pos += 1
        return Token.new(Sqlite3Parser::TK::DOT, '.', start, 1)
      else
        raise "Unexpected character: #{@sql[@pos]}"
      end
    end
  end
end
