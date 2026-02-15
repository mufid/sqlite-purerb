# frozen_string_literal: true

module SqlitePurerb
  module CodeGenerators
    module CompileWhere
      OP = VDBE::OP

      private

      def compile_where_filter(expr, cursor, table_columns, column_affinities, alias_map, and_jumps)
        case expr
        when AST::BinaryExpr
          compile_binary_filter(expr, cursor, table_columns, column_affinities, alias_map)
        when AST::AndExpr
          left_jump = compile_where_filter(expr.left, cursor, table_columns, column_affinities, alias_map, and_jumps)
          and_jumps << left_jump if left_jump
          right_jump = compile_where_filter(expr.right, cursor, table_columns, column_affinities, alias_map, and_jumps)
          and_jumps << right_jump if right_jump
          right_jump
        when AST::OrExpr
          compile_or_filter(expr, cursor, table_columns, column_affinities, alias_map)
        else
          raise "Unknown WHERE expression type: #{expr.class}"
        end
      end

      def compile_binary_filter(expr, cursor, table_columns, column_affinities, alias_map)
        left_reg = compile_filter_value(expr.left, cursor, table_columns, alias_map)
        right_reg = compile_filter_value(expr.right, cursor, table_columns, alias_map)

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

        # Determine P4/P5 for comparison (text vs numeric affinity)
        p4_val = nil
        p5_val = 0
        if expr.right.is_a?(AST::Literal) && expr.right.value.is_a?(String)
          p4_val = 'BINARY-8'
          p5_val = 82  # 0x52 = SQLITE_AFF_TEXT | SQLITE_JUMPIFNULL
        end

        @program.add(op, p1: right_reg, p2: 0, p3: left_reg, p4: p4_val, p5: p5_val,
                     comment: "if r[#{left_reg}]!=r[#{right_reg}] goto %s")
      end

      def compile_or_filter(expr, cursor, table_columns, column_affinities, alias_map)
        left_reg = allocate_register
        right_reg = allocate_register
        result_reg = allocate_register

        compile_where_to_reg(expr.left, cursor, table_columns, column_affinities, alias_map, left_reg)
        compile_where_to_reg(expr.right, cursor, table_columns, column_affinities, alias_map, right_reg)

        @program.add(OP::OR, p1: left_reg, p2: right_reg, p3: result_reg)
        @program.add(OP::IF_NOT, p1: result_reg, p2: 0)
      end

      def compile_where_to_reg(expr, cursor, table_columns, column_affinities, alias_map, result_reg)
        case expr
        when AST::BinaryExpr
          left_reg = compile_filter_value(expr.left, cursor, table_columns, alias_map)
          right_reg = compile_filter_value(expr.right, cursor, table_columns, alias_map)
          @program.add(OP::INTEGER, p1: 0, p2: result_reg)

          op = case expr.operator
               when '=' then OP::EQ
               when '!=' then OP::NE
               when '<' then OP::LT
               when '<=' then OP::LE
               when '>' then OP::GT
               when '>=' then OP::GE
               else raise "Unknown operator: #{expr.operator}"
               end

          jump_addr = @program.add(op, p1: right_reg, p2: 0, p3: left_reg)
          skip_addr = @program.add(OP::GOTO, p2: 0)
          set_true_addr = @program.add(OP::INTEGER, p1: 1, p2: result_reg)
          @program.patch(jump_addr, p2: set_true_addr)
          @program.patch(skip_addr, p2: set_true_addr + 1)
        when AST::AndExpr
          lt = allocate_register
          rt = allocate_register
          compile_where_to_reg(expr.left, cursor, table_columns, column_affinities, alias_map, lt)
          compile_where_to_reg(expr.right, cursor, table_columns, column_affinities, alias_map, rt)
          @program.add(OP::AND, p1: lt, p2: rt, p3: result_reg)
        when AST::OrExpr
          lt = allocate_register
          rt = allocate_register
          compile_where_to_reg(expr.left, cursor, table_columns, column_affinities, alias_map, lt)
          compile_where_to_reg(expr.right, cursor, table_columns, column_affinities, alias_map, rt)
          @program.add(OP::OR, p1: lt, p2: rt, p3: result_reg)
        else
          raise "Unknown expression type: #{expr.class}"
        end
      end

      def compile_filter_value(node, cursor, table_columns, alias_map)
        reg = allocate_register

        case node
        when AST::ColumnRef
          col_name = node.name.downcase
          actual_col = alias_map[col_name] || col_name
          col_index = table_columns.index { |c| c.downcase == actual_col }
          raise "Column not found: #{node.name}" unless col_index

          @max_col_index = col_index if col_index > @max_col_index
          @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: reg,
                       comment: "r[#{reg}]= cursor #{cursor} column #{col_index}")
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
        else
          raise "Unknown value type: #{node.class}"
        end

        reg
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
