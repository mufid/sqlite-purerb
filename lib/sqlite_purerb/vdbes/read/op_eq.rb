# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpEq
        def self.execute(instr, ctx)
          a = ctx.registers[instr.p3]
          b = ctx.registers[instr.p1]
          if a.nil? || b.nil?
            ctx.pc = instr.p2 if (instr.p5 & 0x10) != 0
          elsif a == b
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
