# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module RecordLayout
      private

      def resolve_sort_keys(order_by_terms, table_columns, alias_map)
        order_by_terms.map do |term|
          col_name = term.column_name.downcase
          actual = alias_map[col_name] || col_name
          col_index = table_columns.index { |c| c.downcase == actual }
          raise "ORDER BY column not found: #{term.column_name}" unless col_index
          { col_index: col_index, direction: term.direction, col_name: actual }
        end
      end

      # Build sorter record layout: [sort_keys..., rowid, non_sort_cols...]
      def build_sorter_record_layout(output_columns, sort_key_col_indices, has_rowid_pk, table_columns)
        layout = []

        # Sort keys first (in ORDER BY order)
        sort_key_col_indices.each do |idx|
          layout << { type: :sort_key, col_index: idx }
        end

        # Rowid (if has INTEGER PRIMARY KEY)
        if has_rowid_pk
          layout << { type: :rowid, col_index: 0 }
        end

        # Non-sort-key columns in table order (skip sort keys and rowid col)
        table_columns.each_with_index do |_col_name, idx|
          next if sort_key_col_indices.include?(idx)
          next if idx == 0 && has_rowid_pk  # rowid already added
          layout << { type: :column, col_index: idx }
        end

        layout
      end

      # Build top-N record layout: [sort_key, seqno, rowid, non_sort_cols...]
      def build_topn_record_layout(output_columns, sort_key_col_indices, has_rowid_pk, table_columns)
        layout = []

        # Sort key first
        sort_key_col_indices.each do |idx|
          layout << { type: :sort_key, col_index: idx }
        end

        # Sequence number (tiebreaker)
        layout << { type: :sequence }

        # Rowid
        if has_rowid_pk
          layout << { type: :rowid, col_index: 0 }
        end

        # Non-sort-key columns in table order
        table_columns.each_with_index do |_col_name, idx|
          next if sort_key_col_indices.include?(idx)
          next if idx == 0 && has_rowid_pk
          layout << { type: :column, col_index: idx }
        end

        layout
      end
    end
  end
end
