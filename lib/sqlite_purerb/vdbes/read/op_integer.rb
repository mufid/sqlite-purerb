# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpInteger
        def self.execute(instr, ctx)
          ctx.registers[instr.p2] = instr.p1
        end
      end
    end
  end
end
