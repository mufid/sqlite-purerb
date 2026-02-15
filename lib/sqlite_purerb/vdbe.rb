# frozen_string_literal: true

module SqlitePurerb
  # VDBE - Virtual Database Engine
  # Executes bytecode instructions against the database
  #
  # This is modeled after SQLite's VDBE (vdbe.c)
  # See: https://www.sqlite.org/opcode.html
  class VDBE
    # Opcodes for the virtual machine
    module OP
      # Program control
      INIT           = 0   # Initialize program, jump to P2
      HALT           = 1   # Stop execution
      GOTO           = 2   # Unconditional jump to P2
      TRANSACTION    = 3   # Begin transaction (no-op for read-only)

      # Cursor operations
      OPEN_READ      = 10  # Open cursor P1 on table with root page P2, P4=num_columns
      REWIND         = 11  # Move cursor P1 to first row, jump to P2 if empty
      NEXT           = 12  # Advance cursor P1 to next row, jump to P2 if more rows
      CLOSE          = 13  # Close cursor P1

      # Column and register operations
      COLUMN         = 20  # Read column P2 from cursor P1 into register P3
      ROWID          = 21  # Store rowid of cursor P1 into register P2
      RESULT_ROW     = 22  # Output registers P1..P1+P2-1 as a result row

      # Load values into registers
      INTEGER        = 30  # Store integer P1 into register P2
      STRING8        = 31  # Store string P4 into register P2
      NULL           = 32  # Store NULL into register P2
      COPY           = 33  # Copy register P1 to register P2

      # Type affinity
      REAL_AFFINITY  = 35  # Convert reg[P1] to float if integer

      # Comparison operations (compare P1 and P3, jump to P2 based on result)
      EQ             = 40  # Jump to P2 if reg[P1] == reg[P3]
      NE             = 41  # Jump to P2 if reg[P1] != reg[P3]
      LT             = 42  # Jump to P2 if reg[P1] < reg[P3]
      LE             = 43  # Jump to P2 if reg[P1] <= reg[P3]
      GT             = 44  # Jump to P2 if reg[P1] > reg[P3]
      GE             = 45  # Jump to P2 if reg[P1] >= reg[P3]

      # Logical operations
      IF             = 50  # Jump to P2 if reg[P1] is true (non-zero, non-null)
      IF_NOT         = 51  # Jump to P2 if reg[P1] is false (zero or null)
      AND            = 52  # reg[P3] = reg[P1] AND reg[P2]
      OR             = 53  # reg[P3] = reg[P1] OR reg[P2]
      NOT            = 54  # reg[P2] = NOT reg[P1]

      # Names for debugging
      NAMES = {
        INIT => 'Init',
        HALT => 'Halt',
        GOTO => 'Goto',
        TRANSACTION => 'Transaction',
        OPEN_READ => 'OpenRead',
        REWIND => 'Rewind',
        NEXT => 'Next',
        CLOSE => 'Close',
        COLUMN => 'Column',
        ROWID => 'Rowid',
        RESULT_ROW => 'ResultRow',
        INTEGER => 'Integer',
        STRING8 => 'String8',
        NULL => 'Null',
        COPY => 'Copy',
        REAL_AFFINITY => 'RealAffinity',
        EQ => 'Eq',
        NE => 'Ne',
        LT => 'Lt',
        LE => 'Le',
        GT => 'Gt',
        GE => 'Ge',
        IF => 'If',
        IF_NOT => 'IfNot',
        AND => 'And',
        OR => 'Or',
        NOT => 'Not'
      }.freeze
    end

    # A single bytecode instruction
    class Instruction
      attr_accessor :opcode, :p1, :p2, :p3, :p4, :p5, :comment

      def initialize(opcode, p1: 0, p2: 0, p3: 0, p4: nil, p5: 0, comment: nil)
        @opcode = opcode
        @p1 = p1
        @p2 = p2
        @p3 = p3
        @p4 = p4
        @p5 = p5
        @comment = comment
      end

      def to_s
        name = OP::NAMES[@opcode] || "Unknown(#{@opcode})"
        parts = [name.ljust(12)]
        parts << @p1.to_s.rjust(4)
        parts << @p2.to_s.rjust(4)
        parts << @p3.to_s.rjust(4)
        parts << (@p4 ? @p4.inspect : '').ljust(16)
        parts << "# #{@comment}" if @comment
        parts.join(' ')
      end
    end

    # A compiled program (sequence of instructions)
    class Program
      attr_reader :instructions, :column_names

      def initialize
        @instructions = []
        @column_names = []
      end

      def add(opcode, p1: 0, p2: 0, p3: 0, p4: nil, p5: 0, comment: nil)
        instr = Instruction.new(opcode, p1: p1, p2: p2, p3: p3, p4: p4, p5: p5, comment: comment)
        @instructions << instr
        @instructions.length - 1  # Return address of this instruction
      end

      def set_column_names(names)
        @column_names = names
      end

      # Update jump target at address
      def patch(addr, p2:)
        @instructions[addr].p2 = p2
      end

      def explain
        lines = ["addr  opcode       p1   p2   p3   p4               comment"]
        lines << "-" * 70
        @instructions.each_with_index do |instr, addr|
          lines << "#{addr.to_s.rjust(4)}  #{instr}"
        end
        lines.join("\n")
      end
    end

    # Cursor for iterating over a table
    class Cursor
      attr_reader :root_page, :rows, :position

      def initialize(btree, root_page, columns, has_rowid_pk)
        @btree = btree
        @root_page = root_page
        @columns = columns
        @has_rowid_pk = has_rowid_pk
        @rows = []
        @position = -1
        load_rows
      end

      def rewind
        @position = 0
        !@rows.empty?
      end

      def next_row
        @position += 1
        @position < @rows.length
      end

      def eof?
        @position >= @rows.length
      end

      def rowid
        return nil if eof?
        @rows[@position][:rowid]
      end

      def column(index)
        return nil if eof?
        @rows[@position][:values][index]
      end

      private

      def load_rows
        @btree.scan_table(@root_page) do |rowid, values|
          # Handle INTEGER PRIMARY KEY (stored as rowid)
          if @has_rowid_pk && @columns.first&.downcase == 'id'
            values = [rowid] + values[1..]
          end
          @rows << { rowid: rowid, values: values }
        end
      end
    end

    attr_reader :btree, :schema

    def initialize(btree, schema)
      @btree = btree
      @schema = schema
    end

    # Execute a compiled program
    def execute(program)
      ctx = Vdbes::ExecutionContext.new(program, @btree, @schema)
      instructions = program.instructions

      while ctx.pc < instructions.length
        instr = instructions[ctx.pc]
        ctx.pc += 1

        handler = Vdbes::DISPATCH[instr.opcode]
        raise "Unknown opcode: #{instr.opcode}" unless handler

        handler.execute(instr, ctx)
        break if ctx.halt
      end

      ctx.results
    end
  end
end
