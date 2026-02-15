# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module EmitHelpers
      OP = VDBE::OP

      private

      # Emit column reads for collection phase (non-sort first, sort keys last)
      def emit_sorter_collection(cursor, record_layout, sort_key_base, table_name,
                                 table_columns, column_affinities, has_rowid_pk, num_sort_keys)
        # Assign registers: sort keys get first slots, non-sort data follows
        # But emit non-sort first, sort keys last (matching C sqlite3 order)

        # First emit non-sort-key columns
        non_sort_offset = sort_key_base + num_sort_keys
        record_layout.each_with_index do |entry, i|
          next if entry[:type] == :sort_key  # handle later
          reg = non_sort_offset
          non_sort_offset += 1

          if entry[:type] == :rowid
            @program.add(OP::ROWID, p1: cursor, p2: reg,
                         comment: "r[#{reg}]=#{table_name}.rowid")
          else
            col_index = entry[:col_index]
            @max_col_index = col_index if col_index > @max_col_index
            @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: reg,
                         comment: "r[#{reg}]= cursor #{cursor} column #{col_index}")
            if column_affinities[col_index] == :real
              @program.add(OP::REAL_AFFINITY, p1: reg)
            end
          end
        end

        # Then emit sort key columns (in ORDER BY order)
        sort_key_entries = record_layout.select { |e| e[:type] == :sort_key }
        sort_key_entries.each_with_index do |entry, i|
          reg = sort_key_base + i
          col_index = entry[:col_index]
          @max_col_index = col_index if col_index > @max_col_index
          @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: reg,
                       comment: "r[#{reg}]= cursor #{cursor} column #{col_index}")
          if column_affinities[col_index] == :real
            @program.add(OP::REAL_AFFINITY, p1: reg)
          end
        end
      end

      # Emit output phase columns from pseudo cursor (reverse output order)
      def emit_sorter_output(pseudo_cursor, output_columns, record_layout, result_base,
                             sort_key_col_indices, has_rowid_pk, table_columns)
        # Build map: output_col_index -> record_position
        col_to_record_pos = {}
        record_layout.each_with_index do |entry, pos|
          col_to_record_pos[entry[:col_index]] = pos if entry[:col_index]
        end

        # Emit in reverse output order
        output_columns.reverse.each_with_index do |col, rev_i|
          output_idx = output_columns.length - 1 - rev_i
          reg = result_base + output_idx
          col_index = col[:column_index]
          record_pos = col_to_record_pos[col_index]

          col_name = col[:output_name].downcase
          @program.add(OP::COLUMN, p1: pseudo_cursor, p2: record_pos, p3: reg,
                       comment: "r[#{reg}]=#{col_name}")
        end
      end

      # Emit output phase columns from ephemeral cursor (reverse output order)
      def emit_topn_output(ephemeral_cursor, output_columns, record_layout, result_base,
                           sort_key_col_indices, has_rowid_pk, table_columns)
        # Build map: col_index -> record_position (skip sequence)
        col_to_record_pos = {}
        record_layout.each_with_index do |entry, pos|
          next if entry[:type] == :sequence
          col_to_record_pos[entry[:col_index]] = pos if entry[:col_index]
        end

        # Emit in reverse output order
        output_columns.reverse.each_with_index do |col, rev_i|
          output_idx = output_columns.length - 1 - rev_i
          reg = result_base + output_idx
          col_index = col[:column_index]
          record_pos = col_to_record_pos[col_index]

          col_name = col[:output_name].downcase
          @program.add(OP::COLUMN, p1: ephemeral_cursor, p2: record_pos, p3: reg,
                       comment: "r[#{reg}]=#{col_name}")
        end
      end

      # Emit column reads for output (simple scan and limit patterns)
      def emit_read_output_columns(cursor, output_columns, result_base, table_name, table_columns,
                                   column_affinities, has_rowid_pk)
        output_columns.each_with_index do |col, i|
          col_index = col[:column_index]
          if col_index == 0 && has_rowid_pk
            @program.add(OP::ROWID, p1: cursor, p2: result_base + i,
                         comment: "r[#{result_base + i}]=#{table_name}.rowid")
          else
            @max_col_index = col_index if col_index > @max_col_index
            @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: result_base + i,
                         comment: "r[#{result_base + i}]= cursor #{cursor} column #{col_index}")
            if column_affinities[col_index] == :real
              @program.add(OP::REAL_AFFINITY, p1: result_base + i)
            end
          end
        end
      end

      # Emit the epilogue: Halt, Transaction, deferred constants, Goto
      def emit_epilogue(init_addr, open_addr, _cursor)
        @program.add(OP::HALT)

        transaction_addr = @program.add(OP::TRANSACTION, p3: 1, p4: 0, p5: 1,
                                         comment: 'usesStmtJournal=0')
        @program.patch(init_addr, p2: transaction_addr)
        @program.instructions[init_addr].comment = "Start at #{transaction_addr}"

        @deferred_constants.each do |dc|
          @program.add(dc[:opcode], p1: dc[:p1], p2: dc[:p2], p4: dc[:p4], comment: dc[:comment])
        end

        # Goto back to the first instruction after Init
        @program.add(OP::GOTO, p2: init_addr + 1)

        @program.instructions[open_addr].p4 = @max_col_index + 1
      end
    end
  end
end
