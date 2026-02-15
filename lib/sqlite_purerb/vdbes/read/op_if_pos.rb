# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIfPos
        def self.execute(instr, ctx)
          # If reg[P1]>0 then reg[P1]-=P3, jump to P2
          if ctx.registers[instr.p1] > 0
            ctx.registers[instr.p1] -= instr.p3
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
