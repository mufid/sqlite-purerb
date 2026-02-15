# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSorterNext
        def self.execute(instr, ctx)
          # P1 = sorter cursor, P2 = jump if more rows
          sorter = ctx.cursors[instr.p1]
          ctx.pc = instr.p2 if sorter.next_row
        end
      end
    end
  end
end
