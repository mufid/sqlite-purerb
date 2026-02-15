# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOffsetLimit
        def self.execute(instr, ctx)
          # P1 = limit reg, P2 = dest reg, P3 = offset reg
          # if reg[P1]>0 then reg[P2]=reg[P1]+max(0,reg[P3]) else reg[P2]=(-1)
          limit = ctx.registers[instr.p1]
          offset = ctx.registers[instr.p3]
          if limit > 0
            ctx.registers[instr.p2] = limit + [0, offset].max
          else
            ctx.registers[instr.p2] = -1
          end
        end
      end
    end
  end
end
