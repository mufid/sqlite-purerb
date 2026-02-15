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
        rowid_record_pos = record_layout.index { |e| e[:type] == :rowid }

        # Emit in reverse output order
        output_columns.reverse.each_with_index do |col, rev_i|
          output_idx = output_columns.length - 1 - rev_i
          reg = result_base + output_idx

          if col[:expr]
            emit_function_from_cursor(pseudo_cursor, col, reg, col_to_record_pos, has_rowid_pk)
          elsif col[:column_index] == :rowid && rowid_record_pos
            @program.add(OP::COLUMN, p1: pseudo_cursor, p2: rowid_record_pos, p3: reg,
                         comment: "r[#{reg}]=rowid")
          else
            col_index = col[:column_index]
            record_pos = col_to_record_pos[col_index]

            col_name = col[:output_name].downcase
            @program.add(OP::COLUMN, p1: pseudo_cursor, p2: record_pos, p3: reg,
                         comment: "r[#{reg}]=#{col_name}")
          end
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
        rowid_record_pos = record_layout.index { |e| e[:type] == :rowid }

        # Emit in reverse output order
        output_columns.reverse.each_with_index do |col, rev_i|
          output_idx = output_columns.length - 1 - rev_i
          reg = result_base + output_idx

          if col[:expr]
            emit_function_from_cursor(ephemeral_cursor, col, reg, col_to_record_pos, has_rowid_pk)
          elsif col[:column_index] == :rowid && rowid_record_pos
            @program.add(OP::COLUMN, p1: ephemeral_cursor, p2: rowid_record_pos, p3: reg,
                         comment: "r[#{reg}]=rowid")
          else
            col_index = col[:column_index]
            record_pos = col_to_record_pos[col_index]

            col_name = col[:output_name].downcase
            @program.add(OP::COLUMN, p1: ephemeral_cursor, p2: record_pos, p3: reg,
                         comment: "r[#{reg}]=#{col_name}")
          end
        end
      end

      # Emit column reads for output (simple scan and limit patterns)
      def emit_read_output_columns(cursor, output_columns, result_base, table_name, table_columns,
                                   column_affinities, has_rowid_pk)
        output_columns.each_with_index do |col, i|
          if col[:expr]
            emit_expr(col[:expr], cursor, table_columns, column_affinities, has_rowid_pk,
                      result_base + i, table_name)
          elsif col[:column_index] == :rowid
            @program.add(OP::ROWID, p1: cursor, p2: result_base + i,
                         comment: "r[#{result_base + i}]=#{table_name}.rowid")
          else
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
      end

      # Emit function call column (read args then apply function)
      def emit_function_column(cursor, col_info, dest_reg, table_name, table_columns,
                               column_affinities, has_rowid_pk)
        func = col_info[:expr]
        arg_indices = col_info[:arg_col_indices]

        arg_base = allocate_registers(arg_indices.length)
        arg_indices.each_with_index do |col_idx, i|
          if col_idx == :star || col_idx == :literal
            # No column read needed
          elsif col_idx == 0 && has_rowid_pk
            @program.add(OP::ROWID, p1: cursor, p2: arg_base + i,
                         comment: "r[#{arg_base + i}]=#{table_name}.rowid")
          else
            @max_col_index = col_idx if col_idx.is_a?(Integer) && col_idx > @max_col_index
            @program.add(OP::COLUMN, p1: cursor, p2: col_idx, p3: arg_base + i,
                         comment: "r[#{arg_base + i}]= cursor #{cursor} column #{col_idx}")
            # Apply column affinity so typeof() sees the correct storage class
            if col_idx.is_a?(Integer) && column_affinities[col_idx] == :real
              @program.add(OP::REAL_AFFINITY, p1: arg_base + i)
            end
          end
        end

        @program.add(OP::FUNCTION, p1: arg_base, p2: 0, p3: dest_reg,
                     p4: func.name.downcase, p5: arg_indices.length,
                     comment: "r[#{dest_reg}]=#{func.name.downcase}(r[#{arg_base}])")
      end

      # Emit function call from a pseudo/ephemeral cursor (sorter/topn output phase)
      def emit_function_from_cursor(cursor, col_info, dest_reg, col_to_record_pos, has_rowid_pk)
        func = col_info[:expr]
        arg_indices = col_info[:arg_col_indices]

        arg_base = allocate_registers(arg_indices.length)
        arg_indices.each_with_index do |col_idx, i|
          if col_idx.is_a?(Integer)
            record_pos = col_to_record_pos[col_idx]
            @program.add(OP::COLUMN, p1: cursor, p2: record_pos, p3: arg_base + i,
                         comment: "r[#{arg_base + i}]= cursor #{cursor} column #{record_pos}")
          end
        end

        @program.add(OP::FUNCTION, p1: arg_base, p2: 0, p3: dest_reg,
                     p4: func.name.downcase, p5: arg_indices.length,
                     comment: "r[#{dest_reg}]=#{func.name.downcase}(r[#{arg_base}])")
      end

      # General expression evaluator - emits opcodes to compute expr result into dest_reg
      def emit_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                    table_name = nil)
        case expr
        when AST::ColumnRef
          emit_column_ref_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk,
                               dest_reg, table_name)
        when AST::Literal
          emit_literal_expr(expr, dest_reg)
        when AST::BinaryExpr
          emit_binary_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                           table_name)
        when AST::UnaryExpr
          emit_unary_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                          table_name)
        when AST::FunctionCall
          col_info = resolve_function_for_emit(expr, table_columns)
          emit_function_column(cursor, col_info, dest_reg, table_name, table_columns,
                               column_affinities, has_rowid_pk)
        else
          raise "Unsupported expression in emit_expr: #{expr.class}"
        end
      end

      def emit_column_ref_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk,
                               dest_reg, table_name)
        col_name = expr.name.downcase
        if %w[rowid _rowid_ oid].include?(col_name) && !table_columns.any? { |c| c.downcase == col_name }
          @program.add(OP::ROWID, p1: cursor, p2: dest_reg,
                       comment: "r[#{dest_reg}]=#{table_name || 'table'}.rowid")
        else
          col_index = table_columns.index { |c| c.downcase == col_name }
          raise "Column not found: #{expr.name}" unless col_index
          @max_col_index = col_index if col_index > @max_col_index
          @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: dest_reg,
                       comment: "r[#{dest_reg}]= cursor #{cursor} column #{col_index}")
          if column_affinities[col_index] == :real
            @program.add(OP::REAL_AFFINITY, p1: dest_reg)
          end
        end
      end

      def emit_literal_expr(expr, dest_reg)
        case expr.value
        when Integer
          @program.add(OP::INTEGER, p1: expr.value, p2: dest_reg,
                       comment: "r[#{dest_reg}]=#{expr.value}")
        when String
          @program.add(OP::STRING8, p2: dest_reg, p4: expr.value,
                       comment: "r[#{dest_reg}]='#{expr.value}'")
        when nil
          @program.add(OP::NULL, p2: dest_reg,
                       comment: "r[#{dest_reg}]=NULL")
        else
          @program.add(OP::INTEGER, p1: expr.value.to_i, p2: dest_reg,
                       comment: "r[#{dest_reg}]=#{expr.value}")
        end
      end

      def emit_binary_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                           table_name)
        left_reg = allocate_register
        right_reg = allocate_register
        emit_expr(expr.left, cursor, table_columns, column_affinities, has_rowid_pk, left_reg,
                  table_name)
        emit_expr(expr.right, cursor, table_columns, column_affinities, has_rowid_pk, right_reg,
                  table_name)

        case expr.operator
        when '=', '==', '!=', '<', '<=', '>', '>='
          mode = comparison_affinity_mode(expr, table_columns, column_affinities)
          op_name = { '=' => 'eq', '==' => 'eq', '!=' => 'ne',
                      '<' => 'lt', '<=' => 'le', '>' => 'gt', '>=' => 'ge' }[expr.operator]
          @program.add(OP::FUNCTION, p1: left_reg, p2: 0, p3: dest_reg,
                       p4: "_cmp_#{op_name}_#{mode}", p5: 2,
                       comment: "r[#{dest_reg}]=r[#{left_reg}]#{expr.operator}r[#{right_reg}]")
        when '+', '-', '*', '/', '%', '||'
          @program.add(OP::FUNCTION, p1: left_reg, p2: 0, p3: dest_reg,
                       p4: "_arith_#{expr.operator}", p5: 2,
                       comment: "r[#{dest_reg}]=r[#{left_reg}]#{expr.operator}r[#{right_reg}]")
        else
          raise "Unsupported binary operator in expression: #{expr.operator}"
        end
      end

      def emit_unary_expr(expr, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                          table_name)
        case expr.operator
        when '+'
          # Unary plus is a no-op (strips affinity but we evaluate the operand raw)
          emit_expr(expr.operand, cursor, table_columns, column_affinities, has_rowid_pk, dest_reg,
                    table_name)
        when '-'
          operand_reg = allocate_register
          emit_expr(expr.operand, cursor, table_columns, column_affinities, has_rowid_pk,
                    operand_reg, table_name)
          @program.add(OP::FUNCTION, p1: operand_reg, p2: 0, p3: dest_reg,
                       p4: '_negate', p5: 1,
                       comment: "r[#{dest_reg}]=-r[#{operand_reg}]")
        end
      end

      NUMERIC_AFFINITIES = %i[numeric integer real].freeze

      # Determine the type affinity of an expression (mirrors sqlite3ExprAffinity in C)
      # Column references return their declared affinity; expressions/literals return :none
      def expr_affinity(expr, table_columns, column_affinities)
        case expr
        when AST::ColumnRef
          col_name = expr.name.downcase
          if %w[rowid _rowid_ oid].include?(col_name) && !table_columns.any? { |c| c.downcase == col_name }
            :integer
          else
            col_index = table_columns.index { |c| c.downcase == col_name }
            return :none unless col_index
            column_affinities[col_index] || :blob
          end
        when AST::UnaryExpr
          :none # unary + strips affinity
        else
          :none # literals, function calls, binary exprs have no affinity
        end
      end

      # Determine comparison affinity mode (mirrors sqlite3CompareAffinity in C)
      # Returns :numeric, :text, or :blob
      def comparison_affinity_mode(expr, table_columns, column_affinities)
        left_aff = expr_affinity(expr.left, table_columns, column_affinities)
        right_aff = expr_affinity(expr.right, table_columns, column_affinities)

        left_is_col = left_aff != :none
        right_is_col = right_aff != :none

        if left_is_col && right_is_col
          # Both sides are columns with affinity
          if NUMERIC_AFFINITIES.include?(left_aff) || NUMERIC_AFFINITIES.include?(right_aff)
            :numeric
          else
            :blob
          end
        else
          # At least one side has no affinity - use the column's affinity
          col_aff = left_is_col ? left_aff : (right_is_col ? right_aff : :none)
          case col_aff
          when :integer, :real, :numeric then :numeric
          when :text then :text
          else :blob
          end
        end
      end

      def resolve_function_for_emit(func, table_columns)
        arg_col_indices = func.args.map do |arg|
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
        { expr: func, arg_col_indices: arg_col_indices }
      end

      # Emit the epilogue: Halt, Transaction, deferred constants, Goto
      def emit_epilogue(init_addr, open_addr, _cursor)
        @program.add(OP::HALT)

        transaction_addr = @program.add(OP::TRANSACTION, p3: @schema_cookie, p4: 0, p5: 1,
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
