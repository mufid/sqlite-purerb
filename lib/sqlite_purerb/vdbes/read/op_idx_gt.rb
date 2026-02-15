# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpIdxGT
        def self.execute(instr, ctx)
          # P1 = index cursor
          # P2 = jump target if current entry > key
          # P3 = start register of key
          # P4 = number of key columns to compare
          cursor = ctx.cursors[instr.p1]

          if cursor.eof?
            ctx.pc = instr.p2
            return
          end

          num_keys = instr.p4.to_i
          key_values = (0...num_keys).map { |i| ctx.registers[instr.p3 + i] }

          # Compare the first num_keys columns of the current index entry against key
          gt = false
          num_keys.times do |i|
            entry_val = cursor.column(i)
            key_val = key_values[i]
            cmp = compare_values(entry_val, key_val)
            if cmp > 0
              gt = true
              break
            elsif cmp < 0
              break
            end
          end

          ctx.pc = instr.p2 if gt
        end

        def self.compare_values(a, b)
          return 0 if a.nil? && b.nil?
          return -1 if a.nil?
          return 1 if b.nil?
          a_type = sqlite_type_order(a)
          b_type = sqlite_type_order(b)
          return a_type <=> b_type if a_type != b_type
          a <=> b
        end

        def self.sqlite_type_order(val)
          case val
          when NilClass then 0
          when Integer, Float then 1
          when String
            val.encoding == Encoding::BINARY ? 3 : 2
          else 2
          end
        end
      end
    end
  end
end
