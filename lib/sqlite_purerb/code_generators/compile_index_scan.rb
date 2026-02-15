# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileIndexScan
      OP = VDBE::OP

      private

      # ===== Index scan (WHERE equality matches an index) =====
      #
      # Pattern from C sqlite3:
      #   Init -> OpenRead(table) -> OpenRead(index) -> String8(key) ->
      #   SeekGE -> [IdxGT -> DeferredSeek -> IdxRowid -> Column(s) -> ResultRow] -> Next -> Halt ->
      #   Transaction -> Goto
      def compile_index_scan(stmt, table_name, table_info, table_columns, column_affinities,
                             has_rowid_pk, output_columns, alias_map, index_info)
        table_cursor = allocate_cursor
        index_cursor = allocate_cursor

        # Init
        init_addr = @program.add(OP::INIT, p2: 0)

        # OpenRead for table
        open_table_addr = @program.add(OP::OPEN_READ, p1: table_cursor, p2: table_info[:root_page],
                                        p4: 0, comment: "root=#{table_info[:root_page]} iDb=0; #{table_info[:name]}")

        # OpenRead for index
        # P4 = key info string, P5 = OPFLAG_SEEKEQ (2)
        key_info = build_index_key_info(index_info)
        @program.add(OP::OPEN_READ, p1: index_cursor, p2: index_info[:root_page],
                     p4: key_info, p5: 2,
                     comment: "root=#{index_info[:root_page]} iDb=0; #{index_info[:name]}")

        # Extract the equality value from the WHERE clause
        eq_value, _eq_col_index = extract_eq_value(stmt.where_clause, table_columns, alias_map,
                                                   index_info[:columns].first[:col_index])

        # Load search key into register (not deferred - must be before SeekGE)
        key_reg = allocate_register
        if eq_value.is_a?(String)
          @program.add(OP::STRING8, p2: key_reg, p4: eq_value,
                       comment: "r[#{key_reg}]='#{eq_value}'")
        elsif eq_value.is_a?(Integer)
          @program.add(OP::INTEGER, p1: eq_value, p2: key_reg,
                       comment: "r[#{key_reg}]=#{eq_value}")
        end

        # SeekGE on index cursor
        halt_addr_placeholder = 0  # will be patched to Halt
        seek_addr = @program.add(OP::SEEK_GE, p1: index_cursor, p2: halt_addr_placeholder,
                                  p3: key_reg, p4: 1, comment: "key=r[#{key_reg}]")
        loop_start = @program.instructions.length

        # IdxGT - terminate if current entry > key
        idx_gt_addr = @program.add(OP::IDX_GT, p1: index_cursor, p2: halt_addr_placeholder,
                                    p3: key_reg, p4: 1, comment: "key=r[#{key_reg}]")

        # DeferredSeek - bridge index to table cursor
        @program.add(OP::DEFERRED_SEEK, p1: index_cursor, p2: table_cursor,
                     comment: "Move #{table_cursor} to #{index_cursor}.rowid if needed")

        # Now emit the output columns
        # First: IdxRowid to get the rowid into a register
        result_base = allocate_register  # this will be the rowid register
        @program.add(OP::IDX_ROWID, p1: index_cursor, p2: result_base,
                     comment: "r[#{result_base}]=rowid; #{table_name}.rowid")

        # Read remaining output columns
        # We need to read each column from either the table cursor or the index cursor
        idx_col_index = index_info[:columns].first[:col_index]

        output_columns.each_with_index do |col, i|
          next if i == 0 && has_rowid_pk && col[:column_index] == 0  # rowid already loaded

          actual_reg = allocate_register if i > 0 || !(has_rowid_pk && col[:column_index] == 0)
          actual_reg ||= result_base

          if col[:column_index] == idx_col_index
            # Read from index cursor (column 0 of index = the indexed column)
            @max_col_index = col[:column_index] if col[:column_index] > @max_col_index
            @program.add(OP::COLUMN, p1: index_cursor, p2: 0, p3: actual_reg,
                         comment: "r[#{actual_reg}]= cursor #{index_cursor} column 0")
          else
            # Read from table cursor
            @max_col_index = col[:column_index] if col[:column_index] > @max_col_index
            @program.add(OP::COLUMN, p1: table_cursor, p2: col[:column_index], p3: actual_reg,
                         comment: "r[#{actual_reg}]= cursor #{table_cursor} column #{col[:column_index]}")
          end
        end

        # ResultRow
        num_output = output_columns.length
        @program.add(OP::RESULT_ROW, p1: result_base, p2: num_output,
                     comment: "output=r[#{result_base}..#{result_base + num_output - 1}]")

        # Next on index cursor (back to loop start)
        # For index scan: p3=1, p5=0 (differs from table scan p3=0, p5=1)
        @program.add(OP::NEXT, p1: index_cursor, p2: loop_start, p3: 1)

        # Halt
        halt_addr = @program.add(OP::HALT)

        # Patch SeekGE and IdxGT to jump to Halt
        @program.patch(seek_addr, p2: halt_addr)
        @program.patch(idx_gt_addr, p2: halt_addr)

        # Epilogue: Transaction + Goto
        transaction_addr = @program.add(OP::TRANSACTION, p3: @schema_cookie, p4: 0, p5: 1,
                                         comment: 'usesStmtJournal=0')
        @program.patch(init_addr, p2: transaction_addr)
        @program.instructions[init_addr].comment = "Start at #{transaction_addr}"

        @program.add(OP::GOTO, p2: init_addr + 1)

        # Patch OpenRead table P4 to max column index + 1
        @program.instructions[open_table_addr].p4 = @max_col_index + 1
      end

      def build_index_key_info(index_info)
        num_cols = index_info[:columns].length + 1  # indexed columns + rowid
        # Each column (including trailing rowid) gets a direction entry
        # Empty string = ascending BINARY, '-B' = descending
        dirs = index_info[:columns].map { |c| c[:direction] == :desc ? '-B' : '' }
        dirs << ''  # rowid direction (always ascending)
        # Format: k(N,dir1,dir2,...) with empty dirs meaning ascending BINARY
        "k(#{num_cols},#{dirs.join(',')})"
      end

      # Extract the literal value and column index from a WHERE equality expression
      # that matches the given target_col_index
      def extract_eq_value(expr, table_columns, alias_map, target_col_index)
        case expr
        when AST::BinaryExpr
          return [nil, nil] unless expr.operator == '='

          col_ref = nil
          literal = nil
          if expr.left.is_a?(AST::ColumnRef) && expr.right.is_a?(AST::Literal)
            col_ref = expr.left
            literal = expr.right
          elsif expr.right.is_a?(AST::ColumnRef) && expr.left.is_a?(AST::Literal)
            col_ref = expr.right
            literal = expr.left
          end
          return [nil, nil] unless col_ref && literal

          col_name = col_ref.name.downcase
          actual_col = alias_map[col_name] || col_name
          col_index = table_columns.index { |c| c.downcase == actual_col }
          return [nil, nil] unless col_index == target_col_index

          [literal.value, col_index]
        when AST::AndExpr
          val, idx = extract_eq_value(expr.left, table_columns, alias_map, target_col_index)
          return [val, idx] if val
          extract_eq_value(expr.right, table_columns, alias_map, target_col_index)
        else
          [nil, nil]
        end
      end
    end
  end
end
