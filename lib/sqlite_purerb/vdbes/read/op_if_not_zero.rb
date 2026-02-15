# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIfNotZero
        def self.execute(instr, ctx)
          # If reg[P1]!=0 then reg[P1]--, jump to P2
          if ctx.registers[instr.p1] != 0
            ctx.registers[instr.p1] -= 1
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
