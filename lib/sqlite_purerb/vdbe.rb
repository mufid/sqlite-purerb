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
      IS_NULL        = 55  # Jump to P2 if reg[P1] is NULL
      NOT_NULL       = 56  # Jump to P2 if reg[P1] is not NULL
      NOOP           = 57  # No operation (marker for IN expressions)

      # Sorter operations (ORDER BY)
      SORTER_OPEN    = 60  # Open sorter cursor P1, P4=key info
      MAKE_RECORD    = 61  # Pack reg[P1..P1+P2-1] into record in reg[P3]
      SORTER_INSERT  = 62  # Insert record reg[P2] into sorter P1
      OPEN_PSEUDO    = 63  # Open pseudo-cursor P1 reading from reg[P2]
      SORTER_SORT    = 64  # Sort the sorter P1, jump to P2 if empty
      SORTER_DATA    = 65  # Copy current sorter P1 data into reg[P2]
      SORTER_NEXT    = 66  # Advance sorter P1, jump to P2 if more rows

      # Limit/Offset operations
      DECR_JUMP_ZERO = 70  # Decrement reg[P1], jump to P2 if zero
      MUST_BE_INT    = 71  # Force reg[P1] to integer
      OFFSET_LIMIT   = 72  # Compute limit+offset: reg[P3] = reg[P1] + max(0, reg[P2])
      IF_POS         = 73  # If reg[P1]>0 then reg[P1]-=P3, jump to P2

      # Ephemeral table operations (ORDER BY + LIMIT)
      OPEN_EPHEMERAL = 80  # Open ephemeral table cursor P1, P4=key info
      SEQUENCE       = 81  # reg[P2] = cursor[P1].seqno++
      IF_NOT_ZERO    = 82  # If reg[P1]!=0 then reg[P1]--, jump to P2
      LAST           = 83  # Move cursor P1 to last entry
      IDX_LE         = 84  # Jump to P2 if key <= reg[P3..P3+P4-1]
      DELETE         = 85  # Delete current row from cursor P1
      SORT           = 86  # Rewind cursor P1 for reading sorted, jump P2 if empty
      IDX_INSERT     = 87  # Insert record reg[P2] into index P1

      # Index scan operations
      SEEK_GE        = 90  # Position cursor P1 to first key >= reg[P3..P3+P4-1], jump P2 if not found
      IDX_GT         = 91  # Jump to P2 if current index key > reg[P3..P3+P4-1]
      DEFERRED_SEEK  = 92  # Extract rowid from index cursor P1, defer seek on table cursor P2
      IDX_ROWID      = 93  # Extract rowid from index cursor P1 into register P2

      # Function operations
      FUNCTION       = 100 # reg[P3] = func(P4)(reg[P1]..reg[P1+P5-1])

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
        NOT => 'Not',
        IS_NULL => 'IsNull',
        NOT_NULL => 'NotNull',
        NOOP => 'Noop',
        SORTER_OPEN => 'SorterOpen',
        MAKE_RECORD => 'MakeRecord',
        SORTER_INSERT => 'SorterInsert',
        OPEN_PSEUDO => 'OpenPseudo',
        SORTER_SORT => 'SorterSort',
        SORTER_DATA => 'SorterData',
        SORTER_NEXT => 'SorterNext',
        DECR_JUMP_ZERO => 'DecrJumpZero',
        MUST_BE_INT => 'MustBeInt',
        OFFSET_LIMIT => 'OffsetLimit',
        IF_POS => 'IfPos',
        OPEN_EPHEMERAL => 'OpenEphemeral',
        SEQUENCE => 'Sequence',
        IF_NOT_ZERO => 'IfNotZero',
        LAST => 'Last',
        IDX_LE => 'IdxLE',
        DELETE => 'Delete',
        SORT => 'Sort',
        IDX_INSERT => 'IdxInsert',
        SEEK_GE => 'SeekGE',
        IDX_GT => 'IdxGT',
        DEFERRED_SEEK => 'DeferredSeek',
        IDX_ROWID => 'IdxRowid',
        FUNCTION => 'Function'
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
