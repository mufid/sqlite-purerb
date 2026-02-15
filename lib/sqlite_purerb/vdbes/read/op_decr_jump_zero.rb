# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpDecrJumpZero
        def self.execute(instr, ctx)
          # Decrement reg[P1], jump to P2 if result is zero
          ctx.registers[instr.p1] -= 1
          ctx.pc = instr.p2 if ctx.registers[instr.p1] == 0
        end
      end
    end
  end
end
