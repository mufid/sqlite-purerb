# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module ColumnResolution
      private

      def resolve_output_columns(select_cols, table_columns)
        columns = []

        if select_cols.nil? || select_cols.empty?
          table_columns.each_with_index do |col_name, i|
            columns << { original_name: col_name, output_name: col_name, column_index: i }
          end
        else
          select_cols.each do |col|
            case col
            when AST::Star
              table_columns.each_with_index do |col_name, i|
                columns << { original_name: col_name, output_name: col_name, column_index: i }
              end
            when AST::Column
              col_name = col.name.downcase
              col_index = table_columns.index { |c| c.downcase == col_name }
              raise "Column not found: #{col.name}" unless col_index
              output_name = col.alias_name || col.name
              columns << { original_name: col.name, output_name: output_name, column_index: col_index }
            else
              raise "Unknown column type: #{col.class}"
            end
          end
        end

        columns
      end

      def build_alias_map(select_cols, table_columns)
        map = {}
        return map if select_cols.nil?
        select_cols.each do |col|
          if col.is_a?(AST::Column) && col.alias_name
            map[col.alias_name.downcase] = col.name.downcase
          end
        end
        map
      end
    end
  end
end
