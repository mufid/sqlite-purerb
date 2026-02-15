# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSequence
        def self.execute(instr, ctx)
          # reg[P2] = cursor[P1].seqno++
          cursor = ctx.cursors[instr.p1]
          ctx.registers[instr.p2] = cursor.seqno
          cursor.seqno += 1
        end
      end
    end
  end
end
