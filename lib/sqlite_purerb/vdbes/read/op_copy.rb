# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpCopy
        def self.execute(instr, ctx)
          ctx.registers[instr.p2] = ctx.registers[instr.p1]
        end
      end
    end
  end
end
