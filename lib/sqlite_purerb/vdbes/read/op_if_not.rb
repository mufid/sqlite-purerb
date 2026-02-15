# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIfNot
        def self.execute(instr, ctx)
          val = ctx.registers[instr.p1]
          ctx.pc = instr.p2 if val.nil? || val == 0
        end
      end
    end
  end
end
