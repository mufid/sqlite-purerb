# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpFunction
        CMP_RE = /\A_cmp_(eq|ne|lt|le|gt|ge)_(numeric|text|blob)\z/

        def self.execute(instr, ctx)
          func_name = instr.p4
          arg_base = instr.p1
          num_args = instr.p5
          dest = instr.p3

          args = (0...num_args).map { |i| ctx.registers[arg_base + i] }

          ctx.registers[dest] = if func_name == 'typeof'
                                  sqlite_typeof(args[0])
                                elsif func_name == '_negate'
                                  negate(args[0])
                                elsif func_name.start_with?('_arith_')
                                  dispatch_arith(func_name, args[0], args[1])
                                elsif (m = CMP_RE.match(func_name))
                                  dispatch_cmp(m[1], m[2].to_sym, args[0], args[1])
                                else
                                  raise "Unknown function: #{func_name}"
                                end
        end

        def self.dispatch_arith(func_name, a, b)
          case func_name
          when '_arith_+'  then arith_add(a, b)
          when '_arith_-'  then arith_sub(a, b)
          when '_arith_*'  then arith_mul(a, b)
          when '_arith_/'  then arith_div(a, b)
          when '_arith_%'  then arith_mod(a, b)
          when '_arith_||' then arith_concat(a, b)
          else raise "Unknown arithmetic function: #{func_name}"
          end
        end

        def self.dispatch_cmp(op, mode, a, b)
          result = sqlite_cmp_with_mode(a, b, mode)
          case op
          when 'eq' then result == 0 ? 1 : 0
          when 'ne' then result != 0 ? 1 : 0
          when 'lt' then result < 0 ? 1 : 0
          when 'le' then result <= 0 ? 1 : 0
          when 'gt' then result > 0 ? 1 : 0
          when 'ge' then result >= 0 ? 1 : 0
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

        def self.negate(val)
          return nil if val.nil?
          case val
          when Integer then -val
          when Float then -val
          else -val.to_i
          end
        end

        def self.arith_add(a, b)
          return nil if a.nil? || b.nil?
          numeric(a) + numeric(b)
        end

        def self.arith_sub(a, b)
          return nil if a.nil? || b.nil?
          numeric(a) - numeric(b)
        end

        def self.arith_mul(a, b)
          return nil if a.nil? || b.nil?
          numeric(a) * numeric(b)
        end

        def self.arith_div(a, b)
          return nil if a.nil? || b.nil?
          bn = numeric(b)
          return nil if bn == 0
          an = numeric(a)
          if an.is_a?(Integer) && bn.is_a?(Integer)
            an / bn
          else
            an.to_f / bn.to_f
          end
        end

        def self.arith_mod(a, b)
          return nil if a.nil? || b.nil?
          bn = numeric(b)
          return nil if bn == 0
          numeric(a) % bn
        end

        def self.arith_concat(a, b)
          return nil if a.nil? || b.nil?
          a.to_s + b.to_s
        end

        def self.numeric(val)
          case val
          when Integer, Float then val
          when String
            val.include?('.') ? val.to_f : val.to_i
          else
            0
          end
        end

        # SQLite-compatible comparison with affinity mode.
        # mode: :numeric - convert strings to numbers before comparing
        #       :text    - convert numbers to text before comparing
        #       :blob    - no conversion, compare by storage class order
        def self.sqlite_cmp_with_mode(a, b, mode)
          return 0 if a.nil? && b.nil?
          return -1 if a.nil?
          return 1 if b.nil?

          case mode
          when :numeric
            a = apply_numeric_affinity(a) if a.is_a?(String)
            b = apply_numeric_affinity(b) if b.is_a?(String)
          when :text
            a = a.to_s if a.is_a?(Integer) || a.is_a?(Float)
            b = b.to_s if b.is_a?(Integer) || b.is_a?(Float)
          # :blob - no conversion
          end

          ta = type_order(a)
          tb = type_order(b)

          if ta == tb
            compare_same_type(a, b)
          elsif (ta <= 2) && (tb <= 2)
            # Both numeric (integer or real)
            a.to_f <=> b.to_f
          else
            ta <=> tb
          end
        end

        # Type ordering: NULL=0, INTEGER=1, REAL=2, TEXT=3, BLOB=4
        def self.type_order(val)
          case val
          when nil then 0
          when Integer then 1
          when Float then 2
          when String
            if val.encoding == Encoding::BINARY || val.encoding == Encoding::ASCII_8BIT
              4
            else
              3
            end
          else
            0
          end
        end

        def self.compare_same_type(a, b)
          a <=> b
        end

        def self.apply_numeric_affinity(val)
          return val unless val.is_a?(String)
          if val =~ /\A-?\d+\z/
            val.to_i
          elsif val =~ /\A-?\d+\.?\d*(?:[eE][+-]?\d+)?\z/
            val.to_f
          else
            val
          end
        end
      end
    end
  end
end
