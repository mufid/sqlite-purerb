# frozen_string_literal: true

module SqlitePurerb
  module AST
    # Base class for all AST nodes
    class Node
    end

    # Represents a SELECT statement
    class SelectStmt < Node
      attr_accessor :columns, :from_table, :where_clause, :order_by, :limit, :offset

      def initialize(columns: nil, from_table: nil, where_clause: nil, order_by: nil, limit: nil, offset: nil)
        @columns = columns      # Array of Column or Star
        @from_table = from_table # String (table name)
        @where_clause = where_clause # Expr or nil
        @order_by = order_by    # Array of OrderByTerm or nil
        @limit = limit          # Integer or nil
        @offset = offset        # Integer or nil
      end
    end

    # Represents an ORDER BY term
    class OrderByTerm < Node
      attr_accessor :column_name, :direction

      def initialize(column_name, direction = :asc)
        @column_name = column_name
        @direction = direction  # :asc or :desc
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

    # Represents IS NULL expression
    class IsNullExpr < Node
      attr_accessor :operand

      def initialize(operand)
        @operand = operand
      end
    end

    # Represents IS NOT NULL expression
    class IsNotNullExpr < Node
      attr_accessor :operand

      def initialize(operand)
        @operand = operand
      end
    end

    # Represents IS <value> expression (NULLEQ comparison)
    class IsExpr < Node
      attr_accessor :left, :right

      def initialize(left, right)
        @left = left
        @right = right
      end
    end

    # Represents IS NOT <value> expression (NULLEQ comparison)
    class IsNotExpr < Node
      attr_accessor :left, :right

      def initialize(left, right)
        @left = left
        @right = right
      end
    end

    # Represents IN (val1, val2) expression
    class InExpr < Node
      attr_accessor :operand, :values

      def initialize(operand, values)
        @operand = operand
        @values = values
      end
    end
  end
end
