# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileSimple
      OP = VDBE::OP

      private

      # ===== Simple scan (no ORDER BY, no LIMIT) =====
      def compile_simple(stmt, table_name, table_info, table_columns, column_affinities,
                         has_rowid_pk, output_columns, alias_map)
        cursor = allocate_cursor

        # Init
        init_addr = @program.add(OP::INIT, p2: 0)

        # OpenRead
        open_addr = @program.add(OP::OPEN_READ, p1: cursor, p2: table_info[:root_page],
                                  p4: 0, comment: "root=#{table_info[:root_page]} iDb=0; #{table_info[:name]}")

        # Rewind
        rewind_addr = @program.add(OP::REWIND, p1: cursor, p2: 0)
        loop_start = @program.instructions.length

        # WHERE filter
        where_jump = nil
        and_jumps = []
        @or_output_jumps = []
        if stmt.where_clause
          where_jump = compile_where_filter(stmt.where_clause, cursor, table_columns, column_affinities, alias_map, and_jumps)
        end

        # Read output columns
        result_base = allocate_registers(output_columns.length)

        # Patch OR output jumps to point to the output block
        output_addr = @program.instructions.length
        @or_output_jumps.each do |addr|
          @program.patch(addr, p2: output_addr)
          instr = @program.instructions[addr]
          instr.comment = instr.comment.sub('%s', output_addr.to_s) if instr.comment
        end

        emit_read_output_columns(cursor, output_columns, result_base, table_name, table_columns,
                                 column_affinities, has_rowid_pk)

        # ResultRow
        @program.add(OP::RESULT_ROW, p1: result_base, p2: output_columns.length,
                     comment: "output=r[#{result_base}..#{result_base + output_columns.length - 1}]")

        # Next
        next_addr = @program.add(OP::NEXT, p1: cursor, p2: loop_start, p5: 1)

        # Patch jumps
        @program.patch(rewind_addr, p2: next_addr + 1)
        patch_where_jumps(where_jump, and_jumps, next_addr)

        # Epilogue
        emit_epilogue(init_addr, open_addr, cursor)
      end
    end
  end
end
