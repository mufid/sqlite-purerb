# frozen_string_literal: true

module SqlitePurerb
  # Database is the main entry point for reading SQLite databases
  class Database
    attr_reader :pager, :btree, :schema, :indexes

    def initialize(file_path)
      @pager = Pager.new(file_path)
      @btree = BTree.new(@pager)
      @indexes = {}
      @schema = read_schema
    end

    def close
      @pager.close
    end

    # Execute a SQL query
    # Supports: SELECT columns FROM table [WHERE conditions]
    # Returns an array of hashes with column names as keys
    #
    # Pipeline: SQL -> Parser -> AST -> CodeGenerator -> Bytecode -> VDBE -> Results
    def execute(sql)
      # Step 1: Parse SQL into AST
      parser = QueryParser.new(sql)
      ast = parser.parse

      # Step 2: Compile AST into VDBE bytecode
      code_gen = CodeGenerator.new(@schema, indexes: @indexes, schema_cookie: @pager.schema_cookie)
      program = code_gen.compile(ast)

      # Step 3: Execute bytecode in VDBE virtual machine
      vm = VDBE.new(@btree, @schema)
      vm.execute(program)
    end

    # Compile a SQL query into a VDBE program (without executing)
    def compile_query(sql)
      parser = QueryParser.new(sql)
      ast = parser.parse

      code_gen = CodeGenerator.new(@schema, indexes: @indexes, schema_cookie: @pager.schema_cookie)
      code_gen.compile(ast)
    end

    # Execute a compiled VDBE program
    def execute_program(program)
      vm = VDBE.new(@btree, @schema)
      vm.execute(program)
    end

    # Show the bytecode that would be executed for a query (like SQLite's EXPLAIN)
    def explain(sql)
      program = compile_query(sql)
      program.explain
    end

    # Get list of tables
    def tables
      @schema.keys
    end

    private

    # Read the schema from sqlite_master (page 1)
    def read_schema
      schema = {}
      raw_indexes = []

      # sqlite_master is always on page 1
      @btree.scan_table(1) do |_rowid, values|
        # sqlite_master columns:
        # 0: type (table, index, trigger, view)
        # 1: name
        # 2: tbl_name
        # 3: rootpage
        # 4: sql
        type = values[0]
        name = values[1]
        tbl_name = values[2]
        root_page = values[3]
        sql = values[4]

        if type == 'table' && name && !name.start_with?('sqlite_')
          columns, has_rowid_pk, column_affinities = parse_create_table(sql)
          schema[name.downcase] = {
            name: name,
            root_page: root_page,
            columns: columns,
            column_affinities: column_affinities,
            has_rowid_pk: has_rowid_pk,
            sql: sql
          }
        elsif type == 'index' && name && sql
          raw_indexes << { name: name, tbl_name: tbl_name, root_page: root_page, sql: sql }
        end
      end

      # Parse indexes after all tables are loaded
      raw_indexes.each do |idx_info|
        index_data = parse_create_index(idx_info[:sql], idx_info[:tbl_name], schema)
        next unless index_data

        index_data[:name] = idx_info[:name]
        index_data[:root_page] = idx_info[:root_page]

        table_key = idx_info[:tbl_name].downcase
        @indexes[table_key] ||= []
        @indexes[table_key] << index_data
      end

      schema
    end

    # Parse CREATE INDEX statement to extract indexed columns
    def parse_create_index(sql, tbl_name, schema)
      return nil unless sql

      match = sql.match(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+["']?(\w+)["']?\s+ON\s+["']?(\w+)["']?\s*\(([^)]+)\)/i)
      return nil unless match

      table_name = match[2].downcase
      table_info = schema[table_name]
      return nil unless table_info

      col_strs = match[3].split(',').map(&:strip)
      indexed_columns = col_strs.map do |col_str|
        parts = col_str.split(/\s+/)
        col_name = parts[0].gsub(/["']/, '')
        direction = parts[1]&.upcase == 'DESC' ? :desc : :asc
        col_index = table_info[:columns].index { |c| c.downcase == col_name.downcase }
        { name: col_name, col_index: col_index, direction: direction }
      end

      {
        table_name: table_name,
        columns: indexed_columns,
        unique: sql.match?(/CREATE\s+UNIQUE\s+INDEX/i)
      }
    end

    # Parse column names from CREATE TABLE statement
    # Returns [columns_array, has_rowid_pk]
    def parse_create_table(sql)
      return [[], false, []] unless sql

      # Ensure string is valid UTF-8
      sql = sql.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      # Match CREATE TABLE name (column_defs)
      match = sql.match(/CREATE\s+TABLE\s+["']?(\w+)["']?\s*\((.+)\)/im)
      return [[], false] unless match

      column_defs_str = match[2]

      # Strip SQL line comments (-- to end of line)
      column_defs_str = column_defs_str.gsub(/--[^\n]*/, '')

      # Split column definitions, handling nested parentheses
      column_defs = []
      depth = 0
      current = ''

      column_defs_str.each_char do |c|
        case c
        when '('
          depth += 1
          current += c
        when ')'
          depth -= 1
          current += c
        when ','
          if depth == 0
            column_defs << current.strip
            current = ''
          else
            current += c
          end
        else
          current += c
        end
      end
      column_defs << current.strip unless current.strip.empty?

      # Parse each column definition
      columns = []
      column_affinities = []
      has_rowid_pk = false

      column_defs.each do |col_def|
        next if col_def.empty?

        col_name = extract_column_name(col_def)
        next if col_name.nil? || constraint?(col_name)

        columns << col_name
        col_type = extract_column_type(col_def)
        column_affinities << determine_affinity(col_type)

        # Check if this is INTEGER PRIMARY KEY (rowid alias)
        if col_def.match?(/\binteger\b.*\bprimary\s+key\b/i)
          has_rowid_pk = true
        end
      end

      [columns, has_rowid_pk, column_affinities]
    end

    def extract_column_name(column_def)
      return nil if column_def.empty?

      # Handle quoted identifiers
      if column_def.start_with?('"')
        match = column_def.match(/\A"([^"]+)"/)
        return match[1] if match
      end

      # First word is the column name
      column_def.split(/\s+/).first
    end

    def extract_column_type(column_def)
      # Remove the column name (first word or quoted identifier)
      rest = if column_def.start_with?('"')
               match = column_def.match(/\A"[^"]+"/)
               match ? column_def[match[0].length..].strip : ''
             else
               parts = column_def.split(/\s+/, 2)
               parts[1]&.strip || ''
             end

      # Handle quoted type names (e.g., "DOUBLE PRECISION")
      if rest.start_with?('"')
        match = rest.match(/\A"([^"]+)"/)
        return match[1] if match
      end

      # Remove constraint keywords and everything after
      rest.sub(/\b(PRIMARY\s+KEY|NOT\s+NULL|DEFAULT|UNIQUE|CHECK|REFERENCES|COLLATE|CONSTRAINT)\b.*/i, '').strip
    end

    # Determine SQLite type affinity from declared column type.
    # Rules from sqlite3AffinityType in build.c:
    #   1. Contains "INT"  -> :integer
    #   2. Contains "CHAR", "CLOB", or "TEXT" -> :text
    #   3. Contains "BLOB" or no type -> :blob
    #   4. Contains "REAL", "FLOA", or "DOUB" -> :real
    #   5. Otherwise -> :numeric
    def determine_affinity(type_str)
      return :blob if type_str.nil? || type_str.empty?

      upper = type_str.upcase
      return :integer if upper.include?('INT')
      return :text if upper.include?('CHAR') || upper.include?('CLOB') || upper.include?('TEXT')
      return :blob if upper.include?('BLOB')
      return :real if upper.include?('REAL') || upper.include?('FLOA') || upper.include?('DOUB')

      :numeric
    end

    def constraint?(name)
      return true if name.nil?

      constraints = %w[PRIMARY FOREIGN UNIQUE CHECK CONSTRAINT]
      constraints.include?(name.upcase)
    end
  end
end
