# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSorterInsert
        def self.execute(instr, ctx)
          # P1 = sorter cursor, P2 = register containing record
          sorter = ctx.cursors[instr.p1]
          record = ctx.registers[instr.p2]
          sorter.insert(record.dup)
        end
      end
    end
  end
end
