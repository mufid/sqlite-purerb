# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOr
        def self.execute(instr, ctx)
          left = ctx.registers[instr.p1]
          right = ctx.registers[instr.p2]
          left_true = !left.nil? && left != 0
          right_true = !right.nil? && right != 0
          ctx.registers[instr.p3] = (left_true || right_true) ? 1 : 0
        end
      end
    end
  end
end
