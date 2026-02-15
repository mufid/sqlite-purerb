# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileWhere
      OP = VDBE::OP

      # Operator symbol for comparison opcode comments
      OPCODE_SYMBOLS = {
        OP::EQ => '==', OP::NE => '!=',
        OP::LT => '<',  OP::LE => '<=',
        OP::GT => '>',  OP::GE => '>='
      }.freeze

      private

      def compile_where_filter(expr, cursor, table_columns, column_affinities, alias_map, and_jumps)
        case expr
        when AST::BinaryExpr
          compile_binary_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::IsNullExpr
          compile_is_null_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::IsNotNullExpr
          compile_is_not_null_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::IsExpr
          compile_is_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::IsNotExpr
          compile_is_not_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::InExpr
          compile_in_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::AndExpr
          left_jump = compile_where_filter(expr.left, cursor, table_columns, column_affinities, alias_map, and_jumps)
          and_jumps << left_jump if left_jump
          right_jump = compile_where_filter(expr.right, cursor, table_columns, column_affinities, alias_map, and_jumps)
          and_jumps << right_jump if right_jump
          right_jump
        when AST::OrExpr
          compile_or_short_circuit(expr, cursor, table_columns, column_affinities, alias_map, and_jumps)
        else
          raise "Unknown WHERE expression type: #{expr.class}"
        end
      end

      # Emit inverted comparison: jump to skip if condition is FALSE
      def compile_binary_filter(expr, cursor, table_columns, column_affinities, alias_map)
        col_reg = emit_where_column(expr.left, cursor, table_columns, alias_map, p5: 0)
        const_reg = emit_where_constant(expr.right)

        # Invert: jump if condition is FALSE
        op = case expr.operator
             when '=' then OP::NE
             when '!=' then OP::EQ
             when '<' then OP::GE
             when '<=' then OP::GT
             when '>' then OP::LE
             when '>=' then OP::LT
             else raise "Unknown operator: #{expr.operator}"
             end

        p4_val, p5_val = comparison_p4p5(expr)

        sym = OPCODE_SYMBOLS[op]
        @program.add(op, p1: const_reg, p2: 0, p3: col_reg, p4: p4_val, p5: p5_val,
                     comment: "if r[#{col_reg}]#{sym}r[#{const_reg}] goto %s")
      end

      # IS NULL: emit Column(p5=128) + NotNull (skip if NOT null)
      def compile_is_null_filter(expr, cursor, table_columns, column_affinities, alias_map)
        col_reg = emit_where_column_for_null_check(expr.operand, cursor, table_columns,
                                                    column_affinities, alias_map)
        @program.add(OP::NOT_NULL, p1: col_reg, p2: 0,
                     comment: "if r[#{col_reg}]!=NULL goto %s")
      end

      # IS NOT NULL: emit Column(p5=128) + IsNull (skip if null)
      def compile_is_not_null_filter(expr, cursor, table_columns, column_affinities, alias_map)
        col_reg = emit_where_column_for_null_check(expr.operand, cursor, table_columns,
                                                    column_affinities, alias_map)
        @program.add(OP::IS_NULL, p1: col_reg, p2: 0,
                     comment: "if r[#{col_reg}]==NULL goto %s")
      end

      # IS value: emit Column + Ne with NULLEQ flag (skip if not IS-equal)
      def compile_is_filter(expr, cursor, table_columns, column_affinities, alias_map)
        col_reg = emit_where_column(expr.left, cursor, table_columns, alias_map, p5: 0)
        const_reg = emit_where_constant(expr.right)

        p5_val = is_comparison_p5(expr.right)
        @program.add(OP::NE, p1: const_reg, p2: 0, p3: col_reg, p4: 'BINARY-8', p5: p5_val,
                     comment: "if r[#{col_reg}]!=r[#{const_reg}] goto %s")
      end

      # IS NOT value: emit Column + Eq with NULLEQ flag (skip if IS-equal)
      def compile_is_not_filter(expr, cursor, table_columns, column_affinities, alias_map)
        col_reg = emit_where_column(expr.left, cursor, table_columns, alias_map, p5: 0)
        const_reg = emit_where_constant(expr.right)

        p5_val = is_comparison_p5(expr.right)
        @program.add(OP::EQ, p1: const_reg, p2: 0, p3: col_reg, p4: 'BINARY-8', p5: p5_val,
                     comment: "if r[#{col_reg}]==r[#{const_reg}] goto %s")
      end

      # IN (val1, val2): Noop + Column + Eq(non-inverted) + Ne(inverted)
      # Only supports 2-value IN expressions
      def compile_in_filter(expr, cursor, table_columns, column_affinities, alias_map)
        raise "IN with #{expr.values.length} values not yet supported (only 2)" unless expr.values.length == 2

        # Noop marker
        @program.add(OP::NOOP, comment: 'begin IN expr')

        # Read column
        col_reg = emit_where_column(expr.operand, cursor, table_columns, alias_map, p5: 0)

        # Determine affinity-only p5 (no JUMPIFNULL for first Eq)
        affinity_p5 = in_affinity_p5(expr.values.first)

        # First value: Eq (non-inverted, jump to output if match)
        # Note: P1=col_reg, P3=const_reg (swapped vs regular comparison)
        const1_reg = emit_where_constant(expr.values[0])
        eq_addr = @program.add(OP::EQ, p1: col_reg, p2: 0, p3: const1_reg,
                               p4: 'BINARY-8', p5: affinity_p5,
                               comment: "if r[#{const1_reg}]==r[#{col_reg}] goto %s")
        @or_output_jumps << eq_addr

        # Last value: Ne (inverted, jump to skip if no match)
        const2_reg = emit_where_constant(expr.values[1])
        @program.add(OP::NE, p1: col_reg, p2: 0, p3: const2_reg,
                     p4: 'BINARY-8', p5: affinity_p5 | 0x10,
                     comment: "if r[#{const2_reg}]!=r[#{col_reg}] goto %s; end IN expr")
      end

      # OR short-circuit: first N-1 branches jump to output if TRUE,
      # last branch jumps to skip if FALSE
      def compile_or_short_circuit(expr, cursor, table_columns, column_affinities, alias_map, and_jumps)
        branches = flatten_or(expr)
        @or_output_jumps ||= []

        # First N-1 branches: non-inverted (jump to output if TRUE)
        branches[0...-1].each do |branch|
          jump_addr = compile_or_branch_true(branch, cursor, table_columns, column_affinities, alias_map)
          @or_output_jumps << jump_addr
        end

        # Last branch: inverted (jump to skip if FALSE)
        compile_or_branch_false(branches.last, cursor, table_columns, column_affinities, alias_map)
      end

      # Non-inverted branch: jump to output if condition is TRUE
      def compile_or_branch_true(expr, cursor, table_columns, column_affinities, alias_map)
        case expr
        when AST::IsNullExpr
          col_reg = emit_where_column_for_null_check(expr.operand, cursor, table_columns,
                                                      column_affinities, alias_map)
          @program.add(OP::IS_NULL, p1: col_reg, p2: 0,
                       comment: "if r[#{col_reg}]==NULL goto %s")
        when AST::IsNotNullExpr
          col_reg = emit_where_column_for_null_check(expr.operand, cursor, table_columns,
                                                      column_affinities, alias_map)
          @program.add(OP::NOT_NULL, p1: col_reg, p2: 0,
                       comment: "if r[#{col_reg}]!=NULL goto %s")
        when AST::BinaryExpr
          col_reg = emit_where_column(expr.left, cursor, table_columns, alias_map, p5: 0)
          const_reg = emit_where_constant(expr.right)
          # Non-inverted: jump if condition is TRUE
          op = case expr.operator
               when '=' then OP::EQ
               when '!=' then OP::NE
               when '<' then OP::LT
               when '<=' then OP::LE
               when '>' then OP::GT
               when '>=' then OP::GE
               else raise "Unknown operator: #{expr.operator}"
               end
          p4_val, p5_val = comparison_p4p5(expr)
          sym = OPCODE_SYMBOLS[op]
          @program.add(op, p1: const_reg, p2: 0, p3: col_reg, p4: p4_val, p5: p5_val,
                       comment: "if r[#{col_reg}]#{sym}r[#{const_reg}] goto %s")
        else
          raise "Unsupported OR branch type: #{expr.class}"
        end
      end

      # Inverted branch (last OR branch): jump to skip if condition is FALSE
      def compile_or_branch_false(expr, cursor, table_columns, column_affinities, alias_map)
        case expr
        when AST::IsNullExpr
          # IS NULL inverted: emit Column + affinity + NotNull (skip if NOT null)
          col_reg = emit_where_column_with_affinity(expr.operand, cursor, table_columns,
                                                     column_affinities, alias_map)
          @program.add(OP::NOT_NULL, p1: col_reg, p2: 0,
                       comment: "if r[#{col_reg}]!=NULL goto %s")
        when AST::IsNotNullExpr
          col_reg = emit_where_column_with_affinity(expr.operand, cursor, table_columns,
                                                     column_affinities, alias_map)
          @program.add(OP::IS_NULL, p1: col_reg, p2: 0,
                       comment: "if r[#{col_reg}]==NULL goto %s")
        when AST::BinaryExpr
          compile_binary_filter(expr, cursor, table_columns, column_affinities, alias_map)
        else
          raise "Unsupported OR branch type: #{expr.class}"
        end
      end

      def flatten_or(expr)
        if expr.is_a?(AST::OrExpr)
          flatten_or(expr.left) + flatten_or(expr.right)
        else
          [expr]
        end
      end

      # Emit Column for a WHERE comparison (p5=0, no affinity for the filter column)
      def emit_where_column(node, cursor, table_columns, alias_map, p5: 0)
        @where_col_reg ||= allocate_register
        col_name = node.name.downcase
        actual_col = alias_map[col_name] || col_name
        col_index = table_columns.index { |c| c.downcase == actual_col }
        raise "Column not found: #{node.name}" unless col_index

        @max_col_index = col_index if col_index > @max_col_index
        @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: @where_col_reg, p5: p5,
                     comment: "r[#{@where_col_reg}]= cursor #{cursor} column #{col_index}")
        @where_col_reg
      end

      # Emit Column for IS NULL/IS NOT NULL check (p5=128, no affinity)
      def emit_where_column_for_null_check(node, cursor, table_columns, column_affinities, alias_map)
        @where_col_reg ||= allocate_register
        col_name = node.name.downcase
        actual_col = alias_map[col_name] || col_name
        col_index = table_columns.index { |c| c.downcase == actual_col }
        raise "Column not found: #{node.name}" unless col_index

        @max_col_index = col_index if col_index > @max_col_index
        @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: @where_col_reg, p5: 128,
                     comment: "r[#{@where_col_reg}]= cursor #{cursor} column #{col_index}")
        @where_col_reg
      end

      # Emit Column for OR last branch: p5=0, apply affinity if needed
      def emit_where_column_with_affinity(node, cursor, table_columns, column_affinities, alias_map)
        @where_col_reg ||= allocate_register
        col_name = node.name.downcase
        actual_col = alias_map[col_name] || col_name
        col_index = table_columns.index { |c| c.downcase == actual_col }
        raise "Column not found: #{node.name}" unless col_index

        @max_col_index = col_index if col_index > @max_col_index
        @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: @where_col_reg,
                     comment: "r[#{@where_col_reg}]= cursor #{cursor} column #{col_index}")
        if column_affinities[col_index] == :real
          @program.add(OP::REAL_AFFINITY, p1: @where_col_reg)
        end
        @where_col_reg
      end

      # Emit a constant value (deferred to epilogue)
      def emit_where_constant(node)
        reg = allocate_register
        case node
        when AST::Literal
          if node.value.is_a?(Integer)
            @deferred_constants << { opcode: OP::INTEGER, p1: node.value, p2: reg, p4: nil,
                                     comment: "r[#{reg}]=#{node.value}" }
          elsif node.value.is_a?(String)
            @deferred_constants << { opcode: OP::STRING8, p1: 0, p2: reg, p4: node.value,
                                     comment: "r[#{reg}]='#{node.value}'" }
          elsif node.value.nil?
            @deferred_constants << { opcode: OP::NULL, p1: 0, p2: reg, p4: nil,
                                     comment: "r[#{reg}]=NULL" }
          else
            @deferred_constants << { opcode: OP::INTEGER, p1: node.value.to_i, p2: reg, p4: nil,
                                     comment: "r[#{reg}]=#{node.value}" }
          end
        when AST::ColumnRef
          # Column-to-column comparison: emit column read
          col_name = node.name.downcase
          col_index = @table_columns&.index { |c| c.downcase == col_name }
          raise "Column not found: #{node.name}" unless col_index

          @program.add(OP::COLUMN, p1: 0, p2: col_index, p3: reg,
                       comment: "r[#{reg}]= cursor 0 column #{col_index}")
        else
          raise "Unknown value type: #{node.class}"
        end
        reg
      end

      # Determine p4 and p5 for comparison opcodes
      def comparison_p4p5(expr)
        if expr.right.is_a?(AST::Literal) && expr.right.value.is_a?(String)
          ['BINARY-8', 82]   # AFF_TEXT(0x42) | JUMPIFNULL(0x10)
        else
          ['BINARY-8', 84]   # AFF_INTEGER(0x44) | JUMPIFNULL(0x10)
        end
      end

      # Determine p5 for IS/IS NOT comparisons (NULLEQ flag)
      def is_comparison_p5(value_node)
        if value_node.is_a?(AST::Literal) && value_node.value.is_a?(String)
          0x80 | 0x42   # NULLEQ | AFF_TEXT = 194
        else
          0x80 | 0x44   # NULLEQ | AFF_INTEGER = 196
        end
      end

      # Determine affinity-only p5 for IN expressions (no JUMPIFNULL)
      def in_affinity_p5(value_node)
        if value_node.is_a?(AST::Literal) && value_node.value.is_a?(String)
          0x42   # AFF_TEXT = 66
        else
          0x44   # AFF_INTEGER = 68
        end
      end

      def patch_where_jumps(where_jump, and_jumps, target)
        return unless where_jump
        if where_jump
          @program.patch(where_jump, p2: target)
          instr = @program.instructions[where_jump]
          instr.comment = instr.comment.sub('%s', target.to_s) if instr.comment
        end
        and_jumps.each do |addr|
          next unless addr
          @program.patch(addr, p2: target)
          instr = @program.instructions[addr]
          instr.comment = instr.comment.sub('%s', target.to_s) if instr.comment
        end
      end
    end
  end
end
