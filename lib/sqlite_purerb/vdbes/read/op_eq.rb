# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpEq
        def self.execute(instr, ctx)
          a = ctx.registers[instr.p3]
          b = ctx.registers[instr.p1]
          if (instr.p5 & 0x80) != 0
            # NULLEQ: NULL == NULL is true, NULL != non-NULL is false
            ctx.pc = instr.p2 if a.nil? && b.nil? || !a.nil? && !b.nil? && a == b
          elsif a.nil? || b.nil?
            ctx.pc = instr.p2 if (instr.p5 & 0x10) != 0
          elsif a == b
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
