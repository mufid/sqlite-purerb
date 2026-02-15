# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileSorter
      OP = VDBE::OP

      private

      # ===== ORDER BY (sorter pattern) =====
      def compile_sorter(stmt, table_name, table_info, table_columns, column_affinities,
                         has_rowid_pk, output_columns, alias_map)
        table_cursor = allocate_cursor
        sorter_cursor = allocate_cursor

        # Resolve sort keys
        sort_keys = resolve_sort_keys(stmt.order_by, table_columns, alias_map)
        num_sort_keys = sort_keys.length
        sort_key_col_indices = sort_keys.map { |sk| sk[:col_index] }

        # Build record layout: [sort_key_0, ..., sort_key_n, rowid, non_sort_col_0, ...]
        record_layout = build_sorter_record_layout(output_columns, sort_key_col_indices,
                                                    has_rowid_pk, table_columns)
        num_record_fields = record_layout.length

        # Key info string
        dirs = sort_keys.map { |sk| sk[:direction] == :desc ? '-B' : 'B' }
        key_info = "k(#{num_sort_keys},#{dirs.join(',')})"
        sorter_p2 = num_record_fields + num_sort_keys + 1

        # Init
        init_addr = @program.add(OP::INIT, p2: 0)

        # SorterOpen
        @program.add(OP::SORTER_OPEN, p1: sorter_cursor, p2: sorter_p2, p4: key_info)

        # OpenRead
        open_addr = @program.add(OP::OPEN_READ, p1: table_cursor, p2: table_info[:root_page],
                                  p4: 0, comment: "root=#{table_info[:root_page]} iDb=0; #{table_info[:name]}")

        # Rewind
        rewind_addr = @program.add(OP::REWIND, p1: table_cursor, p2: 0)
        loop_start = @program.instructions.length

        # WHERE filter (if present)
        where_jump = nil
        and_jumps = []
        if stmt.where_clause
          where_jump = compile_where_filter(stmt.where_clause, table_cursor, table_columns,
                                            column_affinities, alias_map, and_jumps)
        end

        # Compute register layout for collection phase
        sort_key_base = @next_register
        # Allocate registers: sort keys go to first slots, then non-sort data
        allocate_registers(num_record_fields)

        # Result base for output phase (reuses registers after sort keys)
        result_base = sort_key_base + num_sort_keys

        # MakeRecord destination
        make_record_dest = result_base + output_columns.length

        # Pseudo register
        pseudo_reg = make_record_dest + 1

        # Emit collection phase: read non-sort-key columns first, then sort keys last
        # (matching C sqlite3's emission order)
        emit_sorter_collection(table_cursor, record_layout, sort_key_base, table_name,
                               table_columns, column_affinities, has_rowid_pk, num_sort_keys)

        # MakeRecord
        @program.add(OP::MAKE_RECORD, p1: sort_key_base, p2: num_record_fields, p3: make_record_dest,
                     comment: "r[#{make_record_dest}]=mkrec(r[#{sort_key_base}..#{sort_key_base + num_record_fields - 1}])")

        # SorterInsert
        @program.add(OP::SORTER_INSERT, p1: sorter_cursor, p2: make_record_dest,
                     p3: sort_key_base, p4: num_record_fields,
                     comment: "key=r[#{make_record_dest}]")

        # Next
        next_addr = @program.add(OP::NEXT, p1: table_cursor, p2: loop_start, p5: 1)

        # Patch Rewind and WHERE jumps
        @program.patch(rewind_addr, p2: next_addr + 1)
        patch_where_jumps(where_jump, and_jumps, next_addr)

        # === Output phase ===

        # OpenPseudo
        pseudo_cursor = allocate_cursor
        @program.add(OP::OPEN_PSEUDO, p1: pseudo_cursor, p2: pseudo_reg, p3: sorter_p2,
                     comment: "#{sorter_p2} columns in r[#{pseudo_reg}]")

        # SorterSort
        sorter_sort_addr = @program.add(OP::SORTER_SORT, p1: sorter_cursor, p2: 0)
        output_loop_start = @program.instructions.length

        # SorterData
        @program.add(OP::SORTER_DATA, p1: sorter_cursor, p2: pseudo_reg, p3: pseudo_cursor,
                     comment: "r[#{pseudo_reg}]=data")

        # Read columns from pseudo cursor in REVERSE output order
        emit_sorter_output(pseudo_cursor, output_columns, record_layout, result_base,
                           sort_key_col_indices, has_rowid_pk, table_columns)

        # ResultRow
        @program.add(OP::RESULT_ROW, p1: result_base, p2: output_columns.length,
                     comment: "output=r[#{result_base}..#{result_base + output_columns.length - 1}]")

        # SorterNext
        @program.add(OP::SORTER_NEXT, p1: sorter_cursor, p2: output_loop_start)

        # Patch SorterSort to jump to Halt
        halt_addr = @program.instructions.length
        @program.patch(sorter_sort_addr, p2: halt_addr)

        # Halt
        @program.add(OP::HALT)

        # Epilogue
        transaction_addr = @program.add(OP::TRANSACTION, p3: 1, p4: 0, p5: 1,
                                         comment: 'usesStmtJournal=0')
        @program.patch(init_addr, p2: transaction_addr)
        @program.instructions[init_addr].comment = "Start at #{transaction_addr}"

        @deferred_constants.each do |dc|
          @program.add(dc[:opcode], p1: dc[:p1], p2: dc[:p2], p4: dc[:p4], comment: dc[:comment])
        end

        # Goto back to SorterOpen (addr 1)
        @program.add(OP::GOTO, p2: 1)

        # Patch OpenRead P4
        @program.instructions[open_addr].p4 = @max_col_index + 1
      end
    end
  end
end
