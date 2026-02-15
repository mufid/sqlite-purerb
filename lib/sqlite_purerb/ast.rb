# frozen_string_literal: true

module SqlitePurerb
  module AST
    # Base class for all AST nodes
    class Node
    end

    # Represents a SELECT statement
    class SelectStmt < Node
      attr_accessor :columns, :from_table, :where_clause

      def initialize(columns: nil, from_table: nil, where_clause: nil)
        @columns = columns      # Array of Column or Star
        @from_table = from_table # String (table name)
        @where_clause = where_clause # Expr or nil
      end
    end

    # Represents SELECT *
    class Star < Node
    end

    # Represents a selected column with optional alias
    class Column < Node
      attr_accessor :name, :alias_name

      def initialize(name, alias_name = nil)
        @name = name
        @alias_name = alias_name
      end

      def result_name
        @alias_name || @name
      end
    end

    # Represents a column reference in expressions
    class ColumnRef < Node
      attr_accessor :name

      def initialize(name)
        @name = name
      end
    end

    # Represents a literal value (string, number, null)
    class Literal < Node
      attr_accessor :value

      def initialize(value)
        @value = value
      end
    end

    # Represents a binary expression (e.g., column = value)
    class BinaryExpr < Node
      attr_accessor :left, :operator, :right

      def initialize(left, operator, right)
        @left = left
        @operator = operator
        @right = right
      end
    end

    # Represents AND expression
    class AndExpr < Node
      attr_accessor :left, :right

      def initialize(left, right)
        @left = left
        @right = right
      end
    end

    # Represents OR expression
    class OrExpr < Node
      attr_accessor :left, :right

      def initialize(left, right)
        @left = left
        @right = right
      end
    end
  end
end
