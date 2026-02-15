# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSeekGE
        def self.execute(instr, ctx)
          # P1 = index cursor
          # P2 = jump target if not found
          # P3 = start register of key
          # P4 = number of key columns
          cursor = ctx.cursors[instr.p1]
          num_keys = instr.p4.to_i
          key_values = (0...num_keys).map { |i| ctx.registers[instr.p3 + i] }

          unless cursor.seek_ge(key_values)
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
