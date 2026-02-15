# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNot
        def self.execute(instr, ctx)
          val = ctx.registers[instr.p1]
          val_true = !val.nil? && val != 0
          ctx.registers[instr.p2] = val_true ? 0 : 1
        end
      end
    end
  end
end
