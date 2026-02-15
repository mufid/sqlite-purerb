# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileTopN
      OP = VDBE::OP

      private

      # ===== ORDER BY + LIMIT (top-N sort pattern) =====
      def compile_top_n(stmt, table_name, table_info, table_columns, column_affinities,
                        has_rowid_pk, output_columns, alias_map)
        table_cursor = allocate_cursor
        ephemeral_cursor = allocate_cursor

        # Resolve sort keys
        sort_keys = resolve_sort_keys(stmt.order_by, table_columns, alias_map)
        num_sort_keys = sort_keys.length
        sort_key_col_indices = sort_keys.map { |sk| sk[:col_index] }

        # Build record layout for ephemeral: [sort_key, seqno, rowid, non_sort_cols...]
        record_layout = build_topn_record_layout(output_columns, sort_key_col_indices,
                                                  has_rowid_pk, table_columns)
        num_record_fields = record_layout.length

        # Key info
        dirs = sort_keys.map { |sk| sk[:direction] == :desc ? '-B' : 'B' }
        key_info = "k(#{num_sort_keys},#{dirs.join(',')})"
        ephemeral_p2 = num_record_fields + 1

        # Init
        init_addr = @program.add(OP::INIT, p2: 0)

        # OpenEphemeral
        @program.add(OP::OPEN_EPHEMERAL, p1: ephemeral_cursor, p2: ephemeral_p2, p4: key_info,
                     comment: "nColumn=#{ephemeral_p2}")

        # Integer for LIMIT counter
        limit_reg = allocate_register
        @program.add(OP::INTEGER, p1: stmt.limit, p2: limit_reg,
                     comment: "r[#{limit_reg}]=#{stmt.limit}; LIMIT counter")

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

        # Read sort key first
        sort_key_reg = allocate_register
        sk = sort_keys[0]
        @max_col_index = sk[:col_index] if sk[:col_index] > @max_col_index
        @program.add(OP::COLUMN, p1: table_cursor, p2: sk[:col_index], p3: sort_key_reg,
                     comment: "r[#{sort_key_reg}]= cursor #{table_cursor} column #{sk[:col_index]}")
        if column_affinities[sk[:col_index]] == :real
          @program.add(OP::REAL_AFFINITY, p1: sort_key_reg)
        end

        # Sequence
        seq_reg = allocate_register
        @program.add(OP::SEQUENCE, p1: ephemeral_cursor, p2: seq_reg,
                     comment: "r[#{seq_reg}]=cursor[#{ephemeral_cursor}].ctr++")

        # IfNotZero - if limit counter not zero, skip the eviction logic
        if_not_zero_addr = @program.add(OP::IF_NOT_ZERO, p1: limit_reg, p2: 0,
                                         comment: "if r[#{limit_reg}]!=0 then r[#{limit_reg}]--, goto %s")

        # Last - move to last entry in ephemeral
        @program.add(OP::LAST, p1: ephemeral_cursor)

        # IdxLE - if last key <= new sort key, skip (goto Next)
        idx_le_addr = @program.add(OP::IDX_LE, p1: ephemeral_cursor, p2: 0, p3: sort_key_reg,
                                    p4: num_sort_keys, comment: "key=r[#{sort_key_reg}]")

        # Delete - remove worst entry
        @program.add(OP::DELETE, p1: ephemeral_cursor)

        # Patch IfNotZero to jump here (record building)
        record_start = @program.instructions.length
        @program.patch(if_not_zero_addr, p2: record_start)
        @program.instructions[if_not_zero_addr].comment =
          "if r[#{limit_reg}]!=0 then r[#{limit_reg}]--, goto #{record_start}"

        # Read remaining data columns (rowid + non-sort-key cols)
        record_base = sort_key_reg  # record starts with sort key
        data_regs = []
        record_layout.each_with_index do |entry, i|
          next if i == 0  # sort key already read
          next if entry[:type] == :sequence  # seqno already in seq_reg

          reg = allocate_register
          data_regs << reg
          if entry[:type] == :rowid
            @program.add(OP::ROWID, p1: table_cursor, p2: reg,
                         comment: "r[#{reg}]=#{table_info[:name]}.rowid")
          else
            col_index = entry[:col_index]
            @max_col_index = col_index if col_index > @max_col_index
            @program.add(OP::COLUMN, p1: table_cursor, p2: col_index, p3: reg,
                         comment: "r[#{reg}]= cursor #{table_cursor} column #{col_index}")
            if column_affinities[col_index] == :real
              @program.add(OP::REAL_AFFINITY, p1: reg)
            end
          end
        end

        # MakeRecord - pack all record fields
        # Destination register is after the full ephemeral column block
        make_record_dest = record_base + num_record_fields + 1
        @next_register = make_record_dest + 1 if @next_register <= make_record_dest
        @program.add(OP::MAKE_RECORD, p1: record_base, p2: num_record_fields, p3: make_record_dest,
                     comment: "r[#{make_record_dest}]=mkrec(r[#{record_base}..#{record_base + num_record_fields - 1}])")

        # IdxInsert
        @program.add(OP::IDX_INSERT, p1: ephemeral_cursor, p2: make_record_dest,
                     p3: record_base, p4: num_record_fields,
                     comment: "key=r[#{make_record_dest}]")

        # Next
        next_addr = @program.add(OP::NEXT, p1: table_cursor, p2: loop_start, p5: 1)

        # Patch Rewind, IdxLE
        @program.patch(rewind_addr, p2: next_addr + 1)
        @program.patch(idx_le_addr, p2: next_addr)
        patch_where_jumps(where_jump, and_jumps, next_addr)

        # === Output phase ===

        # Sort
        sort_addr = @program.add(OP::SORT, p1: ephemeral_cursor, p2: 0)
        output_loop_start = @program.instructions.length

        # Read columns from ephemeral in reverse output order
        result_base = record_base + 2  # skip sort key and seqno (rowid position)
        emit_topn_output(ephemeral_cursor, output_columns, record_layout, result_base,
                         sort_key_col_indices, has_rowid_pk, table_columns)

        # ResultRow
        @program.add(OP::RESULT_ROW, p1: result_base, p2: output_columns.length,
                     comment: "output=r[#{result_base}..#{result_base + output_columns.length - 1}]")

        # Next on ephemeral
        @program.add(OP::NEXT, p1: ephemeral_cursor, p2: output_loop_start)

        # Patch Sort to jump to Halt
        halt_addr = @program.instructions.length
        @program.patch(sort_addr, p2: halt_addr)

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

        @program.add(OP::GOTO, p2: 1)

        # Patch OpenRead P4
        @program.instructions[open_addr].p4 = @max_col_index + 1
      end
    end
  end
end
