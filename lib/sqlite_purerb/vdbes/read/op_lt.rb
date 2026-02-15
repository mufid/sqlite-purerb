# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpLt
        def self.execute(instr, ctx)
          ctx.pc = instr.p2 if ctx.registers[instr.p3] < ctx.registers[instr.p1]
        end
      end
    end
  end
end
