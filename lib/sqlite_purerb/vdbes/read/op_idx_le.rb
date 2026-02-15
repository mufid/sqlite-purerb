# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIdxLE
        def self.execute(instr, ctx)
          # Jump to P2 if current key of cursor P1 <= reg[P3..P3+P4-1]
          cursor = ctx.cursors[instr.p1]
          num_keys = instr.p4 || 1
          key_values = (0...num_keys).map { |i| ctx.registers[instr.p3 + i] }
          ctx.pc = instr.p2 if cursor.current_key_le?(key_values, num_keys)
        end
      end
    end
  end
end
