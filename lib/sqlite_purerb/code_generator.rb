# frozen_string_literal: true

module SqlitePurerb
  # CodeGenerator compiles AST into VDBE bytecode
  #
  # This is modeled after SQLite's code generator (select.c, where.c, expr.c)
  # Bytecode layout matches C SQLite's EXPLAIN output for each query pattern:
  #   Simple:     Init -> OpenRead -> Rewind -> [body] -> Next -> Halt -> Transaction -> [constants] -> Goto
  #   LIMIT:      Init -> Integer -> OpenRead -> Rewind -> [body] -> DecrJumpZero -> Next -> Halt -> ...
  #   ORDER BY:   Init -> SorterOpen -> OpenRead -> Rewind -> [collect] -> Next -> OpenPseudo -> SorterSort -> [output] -> SorterNext -> Halt -> ...
  #   Top-N:      Init -> OpenEphemeral -> Integer -> OpenRead -> Rewind -> [collect] -> Next -> Sort -> [output] -> Next -> Halt -> ...
  class CodeGenerator
    OP = VDBE::OP

    include CodeGenerators::ColumnResolution
    include CodeGenerators::RecordLayout
    include CodeGenerators::EmitHelpers
    include CodeGenerators::CompileWhere
    include CodeGenerators::CompileSimple
    include CodeGenerators::CompileLimit
    include CodeGenerators::CompileSorter
    include CodeGenerators::CompileTopN
    include CodeGenerators::CompileSelect

    def initialize(schema)
      @schema = schema
      @program = VDBE::Program.new
      @next_register = 1  # Register 0 is reserved
      @next_cursor = 0
    end

    # Compile an AST node into a VDBE program
    def compile(ast)
      case ast
      when AST::SelectStmt
        compile_select(ast)
      else
        raise "Unsupported statement type: #{ast.class}"
      end

      @program
    end

    private

    def allocate_register
      reg = @next_register
      @next_register += 1
      reg
    end

    def allocate_registers(count)
      base = @next_register
      @next_register += count
      base
    end

    def allocate_cursor
      cursor = @next_cursor
      @next_cursor += 1
      cursor
    end
  end
end
