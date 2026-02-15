# frozen_string_literal: true

module SqlitePurerb
  # Executor interprets AST and executes queries against the database
  class Executor
    def initialize(btree, schema)
      @btree = btree
      @schema = schema
    end

    def execute(ast)
      case ast
      when AST::SelectStmt
        execute_select(ast)
      else
        raise "Unsupported statement type: #{ast.class}"
      end
    end

    private

    def execute_select(stmt)
      table_name = stmt.from_table.downcase
      table_info = @schema[table_name]
      raise "Table not found: #{stmt.from_table}" unless table_info

      root_page = table_info[:root_page]
      columns = table_info[:columns]
      has_rowid_pk = table_info[:has_rowid_pk]

      # Determine which columns to select
      select_columns = resolve_select_columns(stmt.columns, columns)

      # Build column alias map for WHERE clause resolution
      alias_map = build_alias_map(stmt.columns, columns)

      rows = []
      @btree.scan_table(root_page) do |rowid, values|
        # Build full row hash with all columns
        full_row = build_row(columns, values, rowid, has_rowid_pk)

        # Apply WHERE filter
        if stmt.where_clause
          next unless evaluate_where(stmt.where_clause, full_row, alias_map)
        end

        # Project selected columns
        row = project_columns(select_columns, full_row)
        rows << row
      end

      rows
    end

    def resolve_select_columns(select_cols, table_columns)
      return table_columns.map { |c| AST::Column.new(c) } if select_cols.nil?

      select_cols.flat_map do |col|
        case col
        when AST::Star
          table_columns.map { |c| AST::Column.new(c) }
        when AST::Column
          [col]
        when AST::FunctionCall
          [col]
        else
          raise "Unknown column type: #{col.class}"
        end
      end
    end

    def build_alias_map(select_cols, table_columns)
      map = {}
      return map if select_cols.nil?

      select_cols.each do |col|
        case col
        when AST::Column
          if col.alias_name
            # Alias points to the original column name
            map[col.alias_name.downcase] = col.name.downcase
          end
        end
      end
      map
    end

    def build_row(columns, values, rowid, has_rowid_pk)
      row = {}
      columns.each_with_index do |col_name, i|
        if col_name == 'id' && has_rowid_pk
          row[col_name] = rowid
        else
          row[col_name] = values[i] if i < values.length
        end
      end
      row
    end

    def project_columns(select_columns, full_row)
      row = {}
      select_columns.each do |col|
        case col
        when AST::FunctionCall
          result_name = col.result_name
          row[result_name] = evaluate_function(col, full_row)
        else
          value = full_row[col.name.downcase]
          result_name = col.result_name
          row[result_name] = value
        end
      end
      row
    end

    def evaluate_function(func, full_row)
      case func.name.downcase
      when 'typeof'
        arg = func.args[0]
        value = case arg
                when AST::ColumnRef then full_row[arg.name.downcase]
                when AST::Literal then arg.value
                else nil
                end
        Vdbes::Read::OpFunction.sqlite_typeof(value)
      else
        raise "Unknown function: #{func.name}"
      end
    end

    def evaluate_where(expr, row, alias_map)
      case expr
      when AST::BinaryExpr
        evaluate_binary(expr, row, alias_map)
      when AST::AndExpr
        evaluate_where(expr.left, row, alias_map) && evaluate_where(expr.right, row, alias_map)
      when AST::OrExpr
        evaluate_where(expr.left, row, alias_map) || evaluate_where(expr.right, row, alias_map)
      else
        raise "Unknown expression type: #{expr.class}"
      end
    end

    def evaluate_binary(expr, row, alias_map)
      left_val = evaluate_value(expr.left, row, alias_map)
      right_val = evaluate_value(expr.right, row, alias_map)

      case expr.operator
      when '='
        left_val == right_val
      when '!=', '<>'
        left_val != right_val
      when '<'
        left_val < right_val
      when '>'
        left_val > right_val
      when '<='
        left_val <= right_val
      when '>='
        left_val >= right_val
      else
        raise "Unknown operator: #{expr.operator}"
      end
    end

    def evaluate_value(node, row, alias_map)
      case node
      when AST::ColumnRef
        col_name = node.name.downcase
        # Check if it's an alias
        actual_col = alias_map[col_name] || col_name
        row[actual_col]
      when AST::Literal
        node.value
      else
        raise "Unknown value type: #{node.class}"
      end
    end
  end
end
