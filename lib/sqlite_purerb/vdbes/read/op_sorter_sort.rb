# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSorterSort
        def self.execute(instr, ctx)
          # P1 = sorter cursor, P2 = jump if empty
          sorter = ctx.cursors[instr.p1]
          sorter.sort!
          ctx.pc = instr.p2 if sorter.empty?
        end
      end
    end
  end
end
