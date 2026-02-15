# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpMakeRecord
        def self.execute(instr, ctx)
          # P1 = first register, P2 = count, P3 = destination register
          values = (0...instr.p2).map { |i| ctx.registers[instr.p1 + i] }
          ctx.registers[instr.p3] = values
        end
      end
    end
  end
end
