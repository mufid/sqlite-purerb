# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIf
        def self.execute(instr, ctx)
          val = ctx.registers[instr.p1]
          ctx.pc = instr.p2 if val && val != 0
        end
      end
    end
  end
end
