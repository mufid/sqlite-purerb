# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIsNull
        def self.execute(instr, ctx)
          ctx.pc = instr.p2 if ctx.registers[instr.p1].nil?
        end
      end
    end
  end
end
