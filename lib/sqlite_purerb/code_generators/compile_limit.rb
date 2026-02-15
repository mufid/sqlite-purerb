# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileLimit
      OP = VDBE::OP

      private

      # ===== LIMIT (with optional OFFSET) =====
      def compile_limit(stmt, table_name, table_info, table_columns, column_affinities,
                        has_rowid_pk, output_columns, alias_map, has_offset)
        cursor = allocate_cursor

        # Init
        init_addr = @program.add(OP::INIT, p2: 0)

        # Integer for LIMIT counter
        limit_reg = allocate_register
        @program.add(OP::INTEGER, p1: stmt.limit, p2: limit_reg,
                     comment: "r[#{limit_reg}]=#{stmt.limit}; LIMIT counter")

        if has_offset
          # Integer for OFFSET
          offset_reg = allocate_register
          @program.add(OP::INTEGER, p1: stmt.offset, p2: offset_reg,
                       comment: "r[#{offset_reg}]=#{stmt.offset}")

          # MustBeInt
          @program.add(OP::MUST_BE_INT, p1: offset_reg, comment: 'OFFSET counter')

          # OffsetLimit
          combined_reg = allocate_register
          @program.add(OP::OFFSET_LIMIT, p1: limit_reg, p2: combined_reg, p3: offset_reg,
                       comment: "if r[#{limit_reg}]>0 then r[#{combined_reg}]=r[#{limit_reg}]+max(0,r[#{offset_reg}]) else r[#{combined_reg}]=(-1); LIMIT+OFFSET")
        end

        # OpenRead
        open_addr = @program.add(OP::OPEN_READ, p1: cursor, p2: table_info[:root_page],
                                  p4: 0, comment: "root=#{table_info[:root_page]} iDb=0; #{table_info[:name]}")

        # Rewind
        rewind_addr = @program.add(OP::REWIND, p1: cursor, p2: 0)
        loop_start = @program.instructions.length

        # IfPos for OFFSET (skip rows)
        if_pos_addr = nil
        if has_offset
          if_pos_addr = @program.add(OP::IF_POS, p1: offset_reg, p2: 0, p3: 1,
                                      comment: "if r[#{offset_reg}]>0 then r[#{offset_reg}]-=1, goto %s; OFFSET")
        end

        # WHERE filter
        where_jump = nil
        and_jumps = []
        if stmt.where_clause
          where_jump = compile_where_filter(stmt.where_clause, cursor, table_columns, column_affinities, alias_map, and_jumps)
        end

        # Read output columns
        result_base = allocate_registers(output_columns.length)
        emit_read_output_columns(cursor, output_columns, result_base, table_name, table_columns,
                                 column_affinities, has_rowid_pk)

        # ResultRow
        @program.add(OP::RESULT_ROW, p1: result_base, p2: output_columns.length,
                     comment: "output=r[#{result_base}..#{result_base + output_columns.length - 1}]")

        # DecrJumpZero
        decr_addr = @program.add(OP::DECR_JUMP_ZERO, p1: limit_reg, p2: 0,
                                  comment: "if (--r[#{limit_reg}])==0 goto %s")

        # Next
        next_addr = @program.add(OP::NEXT, p1: cursor, p2: loop_start, p5: 1)

        # Patch Rewind, DecrJumpZero, IfPos
        halt_addr = next_addr + 1
        @program.patch(rewind_addr, p2: halt_addr)
        @program.patch(decr_addr, p2: halt_addr)
        @program.instructions[decr_addr].comment = "if (--r[#{limit_reg}])==0 goto #{halt_addr}"
        if has_offset && if_pos_addr
          @program.patch(if_pos_addr, p2: next_addr)
          @program.instructions[if_pos_addr].comment =
            "if r[#{offset_reg}]>0 then r[#{offset_reg}]-=1, goto #{next_addr}; OFFSET"
        end

        patch_where_jumps(where_jump, and_jumps, next_addr)

        # Epilogue
        emit_epilogue(init_addr, open_addr, cursor)
      end
    end
  end
end
