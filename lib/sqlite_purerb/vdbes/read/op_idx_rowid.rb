# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIdxRowid
        def self.execute(instr, ctx)
          # P1 = index cursor
          # P2 = register to store rowid
          cursor = ctx.cursors[instr.p1]
          ctx.registers[instr.p2] = cursor.rowid
        end
      end
    end
  end
end
