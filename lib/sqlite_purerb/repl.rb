# frozen_string_literal: true

module SqlitePurerb
  # REPL processes batch SQL input and produces formatted output,
  # matching C sqlite3's behavior for dot-commands and query results.
  #
  # Usage:
  #   repl = REPL.new(db_path)
  #   output = repl.process(input_text)
  class REPL
    def initialize(db_path)
      @db = Database.new(db_path)
      @formatter = Formatter.new
    end

    # Process input text (dot-commands + SQL) and return formatted output
    def process(input_text)
      output = []
      sql_buffer = ''

      input_text.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?('--')

        if stripped.start_with?('.')
          handle_dot_command(stripped)
          next
        end

        sql_buffer += ' ' unless sql_buffer.empty?
        sql_buffer += stripped

        next unless sql_buffer.include?(';')

        sql = sql_buffer.sub(/;\s*\z/, '').strip
        result = execute_and_format(sql)
        output << result if result && !result.empty?
        sql_buffer = ''
      end

      output.join("\n") + "\n"
    end

    def close
      @db.close
    end

    private

    def handle_dot_command(cmd)
      parts = cmd.split(/\s+/, 2)
      case parts[0]
      when '.mode'
        @formatter.mode = (parts[1] || 'list').to_sym
      when '.headers'
        @formatter.headers = (parts[1] == 'on')
      when '.separator'
        @formatter.separator = parts[1] || '|'
      end
    end

    def execute_and_format(sql)
      if sql =~ /\AEXPLAIN\s+/i
        inner_sql = sql.sub(/\AEXPLAIN\s+/i, '')
        program = @db.compile_query(inner_sql)
        @formatter.format_explain(program)
      else
        program = @db.compile_query(sql)
        results = @db.execute_program(program)
        @formatter.format_rows(program.column_names, results)
      end
    end
  end
end
