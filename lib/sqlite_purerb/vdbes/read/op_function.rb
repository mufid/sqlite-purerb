# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpFunction
        def self.execute(instr, ctx)
          func_name = instr.p4
          arg_base = instr.p1
          num_args = instr.p5
          dest = instr.p3

          args = (0...num_args).map { |i| ctx.registers[arg_base + i] }

          ctx.registers[dest] = case func_name
                                when 'typeof'
                                  sqlite_typeof(args[0])
                                else
                                  raise "Unknown function: #{func_name}"
                                end
        end

        def self.sqlite_typeof(value)
          case value
          when nil then 'null'
          when Integer then 'integer'
          when Float then 'real'
          when String
            if value.encoding == Encoding::BINARY || value.encoding == Encoding::ASCII_8BIT
              'blob'
            else
              'text'
            end
          else
            'null'
          end
        end
      end
    end
  end
end
