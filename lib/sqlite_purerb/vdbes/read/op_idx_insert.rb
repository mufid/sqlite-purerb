# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIdxInsert
        def self.execute(instr, ctx)
          # Insert record reg[P2] into index cursor P1
          cursor = ctx.cursors[instr.p1]
          record = ctx.registers[instr.p2]
          cursor.insert(record.dup)
        end
      end
    end
  end
end
