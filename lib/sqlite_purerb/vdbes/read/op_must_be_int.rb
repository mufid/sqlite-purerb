# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpMustBeInt
        def self.execute(instr, ctx)
          # Force reg[P1] to integer
          val = ctx.registers[instr.p1]
          ctx.registers[instr.p1] = val.to_i
        end
      end
    end
  end
end
