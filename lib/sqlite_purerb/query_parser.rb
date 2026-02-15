# frozen_string_literal: true

module SqlitePurerb
  # Simple recursive descent parser for SELECT statements
  # Builds AST nodes for execution
  class QueryParser
    class ParseError < StandardError; end

    def initialize(sql)
      @sql = sql
      @pos = 0
      @tokens = tokenize
      @current = 0
    end

    def parse
      stmt = parse_select
      expect_end
      stmt
    end

    private

    # Tokenizer
    def tokenize
      tokens = []
      pos = 0
      sql = @sql

      while pos < sql.length
        # Skip whitespace
        if sql[pos] =~ /\s/
          pos += 1
          next
        end

        # Keywords and identifiers
        if sql[pos] =~ /[a-zA-Z_]/
          start = pos
          pos += 1 while pos < sql.length && sql[pos] =~ /[a-zA-Z0-9_]/
          word = sql[start...pos]
          type = keyword?(word) ? word.upcase.to_sym : :ID
          tokens << [type, word]
          next
        end

        # Numbers
        if sql[pos] =~ /[0-9]/
          start = pos
          pos += 1 while pos < sql.length && sql[pos] =~ /[0-9.]/
          tokens << [:NUMBER, sql[start...pos]]
          next
        end

        # Strings (single quoted)
        if sql[pos] == "'"
          pos += 1
          start = pos
          while pos < sql.length && sql[pos] != "'"
            pos += 1
          end
          value = sql[start...pos]
          pos += 1 # skip closing quote
          tokens << [:STRING, value]
          next
        end

        # Two-character operators
        if pos + 1 < sql.length
          two = sql[pos, 2]
          case two
          when '!=', '<>', '<=', '>='
            tokens << [two.to_sym, two]
            pos += 2
            next
          when '=='
            tokens << [:EQ, '==']
            pos += 2
            next
          when '||'
            tokens << [:CONCAT, '||']
            pos += 2
            next
          end
        end

        # Single-character operators
        case sql[pos]
        when '*'
          tokens << [:STAR, '*']
        when ','
          tokens << [:COMMA, ',']
        when '('
          tokens << [:LPAREN, '(']
        when ')'
          tokens << [:RPAREN, ')']
        when '='
          tokens << [:EQ, '=']
        when '<'
          tokens << [:LT, '<']
        when '>'
          tokens << [:GT, '>']
        when ';'
          tokens << [:SEMI, ';']
        when '+'
          tokens << [:PLUS, '+']
        when '-'
          tokens << [:MINUS, '-']
        when '/'
          tokens << [:SLASH, '/']
        when '%'
          tokens << [:PERCENT, '%']
        else
          raise ParseError, "Unexpected character: #{sql[pos]}"
        end
        pos += 1
      end

      tokens << [:EOF, nil]
      tokens
    end

    KEYWORDS = %w[SELECT FROM WHERE AND OR AS ORDER BY ASC DESC LIMIT OFFSET IS NOT NULL IN].freeze

    def keyword?(word)
      KEYWORDS.include?(word.upcase)
    end

    # Parser helpers
    def current_token
      @tokens[@current]
    end

    def peek(type)
      current_token[0] == type
    end

    def accept(type)
      if peek(type)
        token = current_token
        @current += 1
        token
      end
    end

    def expect(type)
      token = accept(type)
      raise ParseError, "Expected #{type}, got #{current_token[0]}" unless token
      token
    end

    def expect_end
      accept(:SEMI)
      raise ParseError, "Expected end of query, got #{current_token[0]}" unless peek(:EOF)
    end

    # Grammar rules
    def parse_select
      expect(:SELECT)

      columns = parse_select_columns

      expect(:FROM)
      table_name = expect(:ID)[1]

      where_clause = nil
      if accept(:WHERE)
        where_clause = parse_expr
      end

      order_by = nil
      if accept(:ORDER)
        expect(:BY)
        order_by = parse_order_by_list
      end

      limit = nil
      offset = nil
      if accept(:LIMIT)
        limit = expect(:NUMBER)[1].to_i
        if accept(:OFFSET)
          offset = expect(:NUMBER)[1].to_i
        end
      end

      AST::SelectStmt.new(
        columns: columns,
        from_table: table_name,
        where_clause: where_clause,
        order_by: order_by,
        limit: limit,
        offset: offset
      )
    end

    def parse_select_columns
      columns = []

      if accept(:STAR)
        columns << AST::Star.new
        return columns
      end

      loop do
        col = parse_column
        columns << col
        break unless accept(:COMMA)
      end

      columns
    end

    # Parse a SELECT column: expression with optional alias
    def parse_column
      expr = parse_expr

      alias_name = nil
      if accept(:AS)
        alias_name = expect(:ID)[1]
      elsif peek(:ID)
        # Alias without AS keyword
        alias_name = accept(:ID)[1]
      end

      case expr
      when AST::ColumnRef
        AST::Column.new(expr.name, alias_name)
      when AST::FunctionCall
        expr.alias_name = alias_name
        expr
      else
        AST::ExprColumn.new(expr, alias_name)
      end
    end

    def parse_order_by_list
      terms = []
      loop do
        col_name = expect(:ID)[1]
        direction = :asc
        if accept(:DESC)
          direction = :desc
        else
          accept(:ASC)
        end
        terms << AST::OrderByTerm.new(col_name, direction)
        break unless accept(:COMMA)
      end
      terms
    end

    # Expression grammar with proper precedence (lowest to highest):
    #   expr           → or_expr
    #   or_expr        → and_expr ('OR' and_expr)*
    #   and_expr       → comparison ('AND' comparison)*
    #   comparison     → addition (comp_op addition | IS ... | IN ...)?
    #   addition       → multiplication (('+' | '-' | '||') multiplication)*
    #   multiplication → unary (('*' | '/' | '%') unary)*
    #   unary          → ('+' | '-') unary | primary
    #   primary        → ID ['(' args ')'] | NUMBER | STRING | NULL | '(' expr ')'

    def parse_expr
      parse_or_expr
    end

    def parse_or_expr
      left = parse_and_expr

      while accept(:OR)
        right = parse_and_expr
        left = AST::OrExpr.new(left, right)
      end

      left
    end

    def parse_and_expr
      left = parse_comparison

      while accept(:AND)
        right = parse_comparison
        left = AST::AndExpr.new(left, right)
      end

      left
    end

    def parse_comparison
      left = parse_addition

      # Handle IS NULL / IS NOT NULL / IS value / IS NOT value
      if accept(:IS)
        if accept(:NOT)
          if peek(:NULL)
            accept(:NULL)
            return AST::IsNotNullExpr.new(left)
          else
            right = parse_addition
            return AST::IsNotExpr.new(left, right)
          end
        else
          if peek(:NULL)
            accept(:NULL)
            return AST::IsNullExpr.new(left)
          else
            right = parse_addition
            return AST::IsExpr.new(left, right)
          end
        end
      end

      # Handle IN (val1, val2)
      if accept(:IN)
        expect(:LPAREN)
        values = []
        loop do
          values << parse_addition
          break unless accept(:COMMA)
        end
        expect(:RPAREN)
        return AST::InExpr.new(left, values)
      end

      op = nil
      if accept(:EQ)
        op = '='
      elsif accept(:'!=')
        op = '!='
      elsif accept(:'<>')
        op = '!='
      elsif accept(:LT)
        op = '<'
      elsif accept(:GT)
        op = '>'
      elsif accept(:'<=')
        op = '<='
      elsif accept(:'>=')
        op = '>='
      end

      if op
        right = parse_addition
        AST::BinaryExpr.new(left, op, right)
      else
        left
      end
    end

    def parse_addition
      left = parse_multiplication

      while true
        if accept(:PLUS)
          right = parse_multiplication
          left = AST::BinaryExpr.new(left, '+', right)
        elsif accept(:MINUS)
          right = parse_multiplication
          left = AST::BinaryExpr.new(left, '-', right)
        elsif accept(:CONCAT)
          right = parse_multiplication
          left = AST::BinaryExpr.new(left, '||', right)
        else
          break
        end
      end

      left
    end

    def parse_multiplication
      left = parse_unary

      while true
        if accept(:STAR)
          right = parse_unary
          left = AST::BinaryExpr.new(left, '*', right)
        elsif accept(:SLASH)
          right = parse_unary
          left = AST::BinaryExpr.new(left, '/', right)
        elsif accept(:PERCENT)
          right = parse_unary
          left = AST::BinaryExpr.new(left, '%', right)
        else
          break
        end
      end

      left
    end

    def parse_unary
      if accept(:PLUS)
        operand = parse_unary
        AST::UnaryExpr.new('+', operand)
      elsif accept(:MINUS)
        operand = parse_unary
        AST::UnaryExpr.new('-', operand)
      else
        parse_primary
      end
    end

    def parse_primary
      if (token = accept(:ID))
        # Check for function call: ID followed by LPAREN
        if peek(:LPAREN)
          accept(:LPAREN)
          args = []
          unless peek(:RPAREN)
            loop do
              if peek(:STAR)
                accept(:STAR)
                args << AST::Star.new
              else
                args << parse_expr
              end
              break unless accept(:COMMA)
            end
          end
          expect(:RPAREN)
          AST::FunctionCall.new(token[1], args)
        else
          AST::ColumnRef.new(token[1])
        end
      elsif (token = accept(:STRING))
        AST::Literal.new(token[1])
      elsif (token = accept(:NUMBER))
        value = token[1].include?('.') ? token[1].to_f : token[1].to_i
        AST::Literal.new(value)
      elsif accept(:NULL)
        AST::Literal.new(nil)
      elsif accept(:LPAREN)
        expr = parse_expr
        expect(:RPAREN)
        expr
      else
        raise ParseError, "Unexpected token: #{current_token[0]}"
      end
    end
  end
end
