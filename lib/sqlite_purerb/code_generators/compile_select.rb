# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileSelect
      OP = VDBE::OP

      private

      def compile_select(stmt)
        table_name = stmt.from_table
        table_info = @schema[table_name.downcase]
        raise "Table not found: #{table_name}" unless table_info

        table_columns = table_info[:columns]
        column_affinities = table_info[:column_affinities] || []
        has_rowid_pk = table_info[:has_rowid_pk]

        # Resolve which columns to output and their names
        output_columns = resolve_output_columns(stmt.columns, table_columns)
        column_names = output_columns.map { |c| c[:output_name] }
        @program.set_column_names(column_names)

        # Build alias map for WHERE clause
        alias_map = build_alias_map(stmt.columns, table_columns)

        # Initialize deferred constants (emitted in epilogue)
        @deferred_constants = []
        @max_col_index = 0

        has_order_by = stmt.order_by && !stmt.order_by.empty?

        # Optimization: ORDER BY rowid ASC is the natural table order, skip sorter
        if has_order_by && natural_rowid_order?(stmt.order_by, table_columns)
          has_order_by = false
        end

        has_limit = !stmt.limit.nil?
        has_offset = !stmt.offset.nil? && stmt.offset > 0

        # Query planner: check if we can use an index for this query
        usable_index = nil
        if stmt.where_clause && !has_order_by && !has_limit
          usable_index = find_usable_index(stmt.where_clause, table_name, table_columns, alias_map)
        end

        if usable_index
          compile_index_scan(stmt, table_name, table_info, table_columns, column_affinities,
                             has_rowid_pk, output_columns, alias_map, usable_index)
        elsif has_order_by && has_limit
          compile_top_n(stmt, table_name, table_info, table_columns, column_affinities,
                        has_rowid_pk, output_columns, alias_map)
        elsif has_order_by
          compile_sorter(stmt, table_name, table_info, table_columns, column_affinities,
                         has_rowid_pk, output_columns, alias_map)
        elsif has_limit
          compile_limit(stmt, table_name, table_info, table_columns, column_affinities,
                        has_rowid_pk, output_columns, alias_map, has_offset)
        else
          compile_simple(stmt, table_name, table_info, table_columns, column_affinities,
                         has_rowid_pk, output_columns, alias_map)
        end
      end

      # Simple query planner: find an index usable for WHERE equality constraints
      def find_usable_index(where_clause, table_name, table_columns, alias_map)
        return nil unless @indexes

        table_indexes = @indexes[table_name.downcase]
        return nil unless table_indexes && !table_indexes.empty?

        # Extract equality constraints from WHERE clause
        eq_columns = extract_equality_columns(where_clause, table_columns, alias_map)
        return nil if eq_columns.empty?

        # Find an index whose first column matches an equality constraint
        table_indexes.each do |index_info|
          first_col = index_info[:columns].first
          next unless first_col

          if eq_columns.any? { |ec| ec[:col_index] == first_col[:col_index] }
            return index_info
          end
        end

        nil
      end

      # Check if ORDER BY is just rowid ASC (natural table order)
      def natural_rowid_order?(order_by, table_columns)
        return false unless order_by.length == 1

        term = order_by[0]
        return false unless term.direction == :asc

        name = term.column_name.downcase
        %w[rowid _rowid_ oid].include?(name) && !table_columns.any? { |c| c.downcase == name }
      end

      # Extract column indexes from simple equality WHERE clauses
      def extract_equality_columns(expr, table_columns, alias_map)
        case expr
        when AST::BinaryExpr
          return [] unless expr.operator == '='

          col_ref = nil
          if expr.left.is_a?(AST::ColumnRef)
            col_ref = expr.left
          elsif expr.right.is_a?(AST::ColumnRef)
            col_ref = expr.right
          end
          return [] unless col_ref

          col_name = col_ref.name.downcase
          actual_col = alias_map[col_name] || col_name
          col_index = table_columns.index { |c| c.downcase == actual_col }
          return [] unless col_index

          [{ col_name: actual_col, col_index: col_index }]
        when AST::AndExpr
          extract_equality_columns(expr.left, table_columns, alias_map) +
            extract_equality_columns(expr.right, table_columns, alias_map)
        else
          []
        end
      end
    end
  end
end
