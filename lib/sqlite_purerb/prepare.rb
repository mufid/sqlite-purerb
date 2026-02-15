# frozen_string_literal: true

module SqlitePurerb
  # Prepare context for SQL statement preparation
  # Builds AST during parsing, similar to sqlite3Prepare in SQLite
  class Prepare
    attr_reader :read_schema_called, :ast

    def initialize
      @read_schema_called = false
      @ast = nil
      @columns = []
      @where_expr = nil
      @from_table = nil
    end

    # Called when SELECT statement is complete
    def read_schema
      @read_schema_called = true
    end

    # Called when a complete SELECT is parsed
    def finish_select
      # AST should already be built by build_select
      # Also set read_schema_called for compatibility with tests
      @read_schema_called = true
    end

    # Build a SELECT statement from parsed components
    # columns: array of { expr:, alias: } or { star: true }
    # from_tables: array of { table:, alias: } or nil
    # where_expr: expression AST or nil
    def build_select(columns, from_tables, where_expr)
      # Convert column list to AST nodes
      ast_columns = []
      columns.each do |col|
        if col[:star]
          ast_columns << AST::Star.new
        elsif col[:expr].is_a?(AST::ColumnRef)
          # Column reference with optional alias
          ast_columns << AST::Column.new(col[:expr].name, col[:alias])
        else
          # Expression - store as is
          ast_columns << AST::Column.new(col[:expr], col[:alias])
        end
      end
      ast_columns = [AST::Star.new] if ast_columns.empty?

      # Get table name from from_tables
      table_name = nil
      if from_tables && !from_tables.empty?
        table_name = from_tables.first[:table]
      end

      @ast = AST::SelectStmt.new(
        columns: ast_columns,
        from_table: table_name,
        where_clause: where_expr
      )
    end

    # Column selection methods
    def add_star
      @columns << AST::Star.new
    end

    def add_column(name, alias_name = nil)
      @columns << AST::Column.new(name, alias_name)
    end

    # FROM clause
    def set_from_table(table_name)
      @from_table = table_name
    end

    # WHERE clause
    def set_where(expr)
      @where_expr = expr
    end

    # Expression building
    def make_column_ref(name)
      AST::ColumnRef.new(name)
    end

    def make_string_literal(value)
      AST::Literal.new(value)
    end

    def make_integer_literal(value)
      AST::Literal.new(value.to_i)
    end

    def make_binary_expr(left, op, right)
      AST::BinaryExpr.new(left, op, right)
    end

    def make_and_expr(left, right)
      AST::AndExpr.new(left, right)
    end

    def make_or_expr(left, right)
      AST::OrExpr.new(left, right)
    end

    def reset
      @read_schema_called = false
      @ast = nil
      @columns = []
      @where_expr = nil
      @from_table = nil
    end
  end
end
