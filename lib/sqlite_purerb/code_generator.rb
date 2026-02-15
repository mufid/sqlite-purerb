# frozen_string_literal: true

module SqlitePurerb
  # CodeGenerator compiles AST into VDBE bytecode
  #
  # This is modeled after SQLite's code generator (select.c, where.c, expr.c)
  # Bytecode layout matches C SQLite's EXPLAIN output:
  #   Init -> OpenRead -> Rewind -> [body] -> Next -> Halt -> Transaction -> [constants] -> Goto
  class CodeGenerator
    OP = VDBE::OP

    def initialize(schema)
      @schema = schema
      @program = VDBE::Program.new
      @next_register = 1  # Register 0 is reserved
      @next_cursor = 0
    end

    # Compile an AST node into a VDBE program
    def compile(ast)
      case ast
      when AST::SelectStmt
        compile_select(ast)
      else
        raise "Unsupported statement type: #{ast.class}"
      end

      @program
    end

    private

    def allocate_register
      reg = @next_register
      @next_register += 1
      reg
    end

    def allocate_registers(count)
      base = @next_register
      @next_register += count
      base
    end

    def allocate_cursor
      cursor = @next_cursor
      @next_cursor += 1
      cursor
    end

    def compile_select(stmt)
      table_name = stmt.from_table
      table_info = @schema[table_name.downcase]
      raise "Table not found: #{table_name}" unless table_info

      table_columns = table_info[:columns]
      column_affinities = table_info[:column_affinities] || []
      has_rowid_pk = table_info[:has_rowid_pk]
      cursor = allocate_cursor

      # Resolve which columns to output and their names
      output_columns = resolve_output_columns(stmt.columns, table_columns)
      column_names = output_columns.map { |c| c[:output_name] }
      @program.set_column_names(column_names)

      # Build alias map for WHERE clause (alias -> original column name)
      alias_map = build_alias_map(stmt.columns, table_columns)

      # Initialize deferred constants (emitted in epilogue, before Goto)
      @deferred_constants = []
      # Track max column index for OpenRead P4
      @max_col_index = 0

      # === Bytecode emission ===

      # addr 0: Init - jump target patched to Transaction (epilogue)
      init_addr = @program.add(OP::INIT, p2: 0)

      # OpenRead cursor on table (P4 patched later with column count)
      open_addr = @program.add(OP::OPEN_READ, p1: cursor, p2: table_info[:root_page],
                                p4: 0, comment: "root=#{table_info[:root_page]} iDb=0; #{table_name}")

      # Rewind - go to first row (jump to Halt if empty)
      rewind_addr = @program.add(OP::REWIND, p1: cursor, p2: 0)

      # This is where we'll loop back to for each row
      loop_start = @program.instructions.length

      # Generate WHERE clause filter (if present)
      # WHERE registers are allocated FIRST so they get lower register numbers
      @and_jumps = []
      next_jump_addr = nil
      if stmt.where_clause
        next_jump_addr = compile_where(stmt.where_clause, cursor, table_columns, alias_map)
      end

      # Allocate registers for output columns AFTER WHERE
      result_base = allocate_registers(output_columns.length)

      # Read columns into registers
      output_columns.each_with_index do |col, i|
        col_index = col[:column_index]

        if col_index == 0 && has_rowid_pk
          # INTEGER PRIMARY KEY uses Rowid instead of Column
          @program.add(OP::ROWID, p1: cursor, p2: result_base + i,
                       comment: "r[#{result_base + i}]=#{table_name}.rowid")
        else
          @max_col_index = col_index if col_index > @max_col_index
          @program.add(OP::COLUMN, p1: cursor, p2: col_index, p3: result_base + i,
                       comment: "r[#{result_base + i}]= cursor #{cursor} column #{col_index}")

          # Emit RealAffinity for columns with REAL affinity
          if column_affinities[col_index] == :real
            @program.add(OP::REAL_AFFINITY, p1: result_base + i)
          end
        end
      end

      # Output result row
      @program.add(OP::RESULT_ROW, p1: result_base, p2: output_columns.length,
                   comment: "output=r[#{result_base}..#{result_base + output_columns.length - 1}]")

      # Next - advance cursor (jump back to loop_start if more rows)
      next_addr = @program.add(OP::NEXT, p1: cursor, p2: loop_start, p5: 1)

      # Patch Rewind to jump past Next to Halt
      @program.patch(rewind_addr, p2: next_addr + 1)

      # Patch WHERE jumps to go to Next
      if stmt.where_clause
        @program.patch(next_jump_addr, p2: next_addr) if next_jump_addr
        @and_jumps.each do |addr|
          @program.patch(addr, p2: next_addr) if addr
        end
      end

      # Halt
      @program.add(OP::HALT)

      # === Epilogue ===

      # Transaction (no-op for read-only)
      transaction_addr = @program.add(OP::TRANSACTION, p3: 1, p4: 0, p5: 1,
                                       comment: 'usesStmtJournal=0')

      # Patch Init to jump to Transaction and update its comment
      @program.patch(init_addr, p2: transaction_addr)
      @program.instructions[init_addr].comment = "Start at #{transaction_addr}"

      # Emit deferred constants
      @deferred_constants.each do |dc|
        @program.add(dc[:opcode], p1: dc[:p1], p2: dc[:p2], p4: dc[:p4], comment: dc[:comment])
      end

      # Goto back to OpenRead
      @program.add(OP::GOTO, p2: open_addr)

      # Patch OpenRead P4 with column count (max column index + 1)
      @program.instructions[open_addr].p4 = @max_col_index + 1
    end

    def resolve_output_columns(select_cols, table_columns)
      columns = []

      if select_cols.nil? || select_cols.empty?
        # SELECT * - all columns
        table_columns.each_with_index do |col_name, i|
          columns << { original_name: col_name, output_name: col_name, column_index: i }
        end
      else
        select_cols.each do |col|
          case col
          when AST::Star
            # SELECT * - all columns
            table_columns.each_with_index do |col_name, i|
              columns << { original_name: col_name, output_name: col_name, column_index: i }
            end
          when AST::Column
            # Find column index
            col_name = col.name.downcase
            col_index = table_columns.index { |c| c.downcase == col_name }
            raise "Column not found: #{col.name}" unless col_index

            output_name = col.alias_name || col.name
            columns << { original_name: col.name, output_name: output_name, column_index: col_index }
          else
            raise "Unknown column type: #{col.class}"
          end
        end
      end

      columns
    end

    def build_alias_map(select_cols, table_columns)
      map = {}
      return map if select_cols.nil?

      select_cols.each do |col|
        if col.is_a?(AST::Column) && col.alias_name
          map[col.alias_name.downcase] = col.name.downcase
        end
      end
      map
    end

    # Compile WHERE clause
    # Returns the address of the jump instruction that needs to be patched
    # to jump to Next when condition is false
    def compile_where(expr, cursor, table_columns, alias_map)
      case expr
      when AST::BinaryExpr
        compile_binary_expr(expr, cursor, table_columns, alias_map)
      when AST::AndExpr
        compile_and_expr(expr, cursor, table_columns, alias_map)
      when AST::OrExpr
        compile_or_expr(expr, cursor, table_columns, alias_map)
      else
        raise "Unknown WHERE expression type: #{expr.class}"
      end
    end

    def compile_binary_expr(expr, cursor, table_columns, alias_map)
      # Load left operand into register
      left_reg = compile_value(expr.left, cursor, table_columns, alias_map)

      # Load right operand into register
      right_reg = compile_value(expr.right, cursor, table_columns, alias_map)

      # Generate comparison that jumps to Next if false
      # We invert the condition: if condition is true, fall through; if false, jump
      # C convention: Op P1 P2 P3 -> jump to P2 if r[P3] op r[P1]
      # P1 = right operand (constant), P3 = left operand (column)
      op = case expr.operator
           when '=' then OP::NE   # Jump if NOT equal
           when '!=' then OP::EQ  # Jump if equal
           when '<' then OP::GE   # Jump if >= (not less than)
           when '<=' then OP::GT  # Jump if > (not less than or equal)
           when '>' then OP::LE   # Jump if <= (not greater than)
           when '>=' then OP::LT  # Jump if < (not greater than or equal)
           else raise "Unknown operator: #{expr.operator}"
           end

      # Jump to Next (address will be patched later)
      # C convention: P1=right_reg, P3=left_reg
      @program.add(op, p1: right_reg, p2: 0, p3: left_reg,
                   comment: "if r[#{left_reg}]!=r[#{right_reg}] goto ")
    end

    def compile_and_expr(expr, cursor, table_columns, alias_map)
      # For AND: if left is false, skip to Next; otherwise check right
      @and_jumps ||= []

      left_jump = compile_where(expr.left, cursor, table_columns, alias_map)
      @and_jumps << left_jump if left_jump

      right_jump = compile_where(expr.right, cursor, table_columns, alias_map)
      @and_jumps << right_jump if right_jump

      right_jump
    end

    def compile_or_expr(expr, cursor, table_columns, alias_map)
      # For OR: evaluate both into registers, then OR them
      left_reg = allocate_register
      right_reg = allocate_register
      result_reg = allocate_register

      compile_where_to_register(expr.left, cursor, table_columns, alias_map, left_reg)
      compile_where_to_register(expr.right, cursor, table_columns, alias_map, right_reg)

      @program.add(OP::OR, p1: left_reg, p2: right_reg, p3: result_reg,
                   comment: 'OR left and right')

      @program.add(OP::IF_NOT, p1: result_reg, p2: 0, comment: 'Jump if OR is false')
    end

    def compile_where_to_register(expr, cursor, table_columns, alias_map, result_reg)
      case expr
      when AST::BinaryExpr
        left_reg = compile_value(expr.left, cursor, table_columns, alias_map)
        right_reg = compile_value(expr.right, cursor, table_columns, alias_map)

        # Set result to 0 (false)
        @program.add(OP::INTEGER, p1: 0, p2: result_reg, comment: 'Assume false')

        op = case expr.operator
             when '=' then OP::EQ
             when '!=' then OP::NE
             when '<' then OP::LT
             when '<=' then OP::LE
             when '>' then OP::GT
             when '>=' then OP::GE
             else raise "Unknown operator: #{expr.operator}"
             end

        # Jump to set_true if condition matches
        # C convention: P1=right_reg, P3=left_reg
        jump_addr = @program.add(op, p1: right_reg, p2: 0, p3: left_reg,
                                 comment: 'Jump if condition true')

        # Skip over set_true
        skip_addr = @program.add(OP::GOTO, p2: 0, comment: 'Skip set_true')

        # Set to true
        set_true_addr = @program.add(OP::INTEGER, p1: 1, p2: result_reg, comment: 'Set to true')

        # Patch jumps
        @program.patch(jump_addr, p2: set_true_addr)
        @program.patch(skip_addr, p2: set_true_addr + 1)

        nil
      when AST::AndExpr
        left_temp = allocate_register
        right_temp = allocate_register

        compile_where_to_register(expr.left, cursor, table_columns, alias_map, left_temp)
        compile_where_to_register(expr.right, cursor, table_columns, alias_map, right_temp)

        @program.add(OP::AND, p1: left_temp, p2: right_temp, p3: result_reg)
        nil
      when AST::OrExpr
        left_temp = allocate_register
        right_temp = allocate_register

        compile_where_to_register(expr.left, cursor, table_columns, alias_map, left_temp)
        compile_where_to_register(expr.right, cursor, table_columns, alias_map, right_temp)

        @program.add(OP::OR, p1: left_temp, p2: right_temp, p3: result_reg)
        nil
      else
        raise "Unknown expression type: #{expr.class}"
      end
    end

    def compile_value(node, cursor, table_columns, alias_map)
      reg = allocate_register

      case node
      when AST::ColumnRef
        col_name = node.name.downcase
        # Check if it's an alias
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
  end
end
