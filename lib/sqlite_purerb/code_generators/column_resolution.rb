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
              if %w[rowid _rowid_ oid].include?(col_name) && !table_columns.any? { |c| c.downcase == col_name }
                output_name = col.alias_name || col.name
                columns << { output_name: output_name, column_index: :rowid }
              else
                col_index = table_columns.index { |c| c.downcase == col_name }
                raise "Column not found: #{col.name}" unless col_index
                output_name = col.alias_name || col.name
                columns << { original_name: col.name, output_name: output_name, column_index: col_index }
              end
            when AST::ExprColumn
              output_name = col.result_name
              columns << { output_name: output_name, column_index: nil, expr: col.expr }
            when AST::FunctionCall
              arg_col_indices = col.args.map do |arg|
                case arg
                when AST::ColumnRef
                  idx = table_columns.index { |c| c.downcase == arg.name.downcase }
                  raise "Column not found: #{arg.name}" unless idx
                  idx
                when AST::Star
                  :star
                when AST::Literal
                  :literal
                else
                  raise "Unsupported function argument: #{arg.class}"
                end
              end
              output_name = col.result_name
              columns << { output_name: output_name, column_index: nil, expr: col, arg_col_indices: arg_col_indices }
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
