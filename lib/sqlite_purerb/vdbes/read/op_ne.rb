# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNe
        def self.execute(instr, ctx)
          a = ctx.registers[instr.p3]
          b = ctx.registers[instr.p1]
          if (instr.p5 & 0x80) != 0
            # NULLEQ: NULL != non-NULL is true, NULL != NULL is false
            if a.nil? && b.nil?
              # equal, don't jump
            elsif a.nil? || b.nil?
              ctx.pc = instr.p2
            elsif a != b
              ctx.pc = instr.p2
            end
          elsif a.nil? || b.nil?
            ctx.pc = instr.p2 if (instr.p5 & 0x10) != 0
          elsif a != b
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
