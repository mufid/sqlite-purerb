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
        has_limit = !stmt.limit.nil?
        has_offset = !stmt.offset.nil? && stmt.offset > 0

        if has_order_by && has_limit
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
    end
  end
end
