#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts do_test / do_execsql_test blocks from SQLite TCL test files
# and generates files runnable by both C sqlite3 and sqlite-purerb's REPL.
#
# Supported patterns:
#   do_test NAME { db eval { SQL } } {EXPECTED}
#   do_test NAME { execsql { SQL } } {EXPECTED}
#   do_test NAME { execsql {SQL1} \n execsql {SQL2} } {EXPECTED}
#   do_execsql_test NAME { SQL } {EXPECTED}
#   bare execsql { SQL }  (top-level setup, no test wrapper)
#
# Skipped patterns:
#   catchsql, catch {execsql ...}, do_catchsql_test
#   double-quoted SQL (variable interpolation)
#   tests with regex expected output ({~/pattern/})
#   tests with TCL variables in expected output

require 'json'
require 'fileutils'
require 'tempfile'
require 'set'

class TclTestExtractor
  SQLITE3_BIN = File.expand_path('../../sqlite-c/bld/sqlite3', __dir__)

  def initialize(output_dir, excluded_tests: [])
    @output_dir = output_dir
    @excluded_tests = excluded_tests.to_set
  end

  # Extract tests from a single TCL file. Returns stats hash.
  def extract(tcl_file)
    content = File.read(tcl_file)
    basename = File.basename(tcl_file, '.test')
    testprefix = detect_testprefix(content, basename)

    items = parse_all(content, testprefix)
    return nil if items.empty?

    FileUtils.mkdir_p(@output_dir)

    accumulated_sql = ''
    db_dirty = false
    db_counter = 0
    current_db_name = nil
    manifest = {}
    setup_count = 0
    query_count = 0
    error_count = 0

    items.each do |item|
      case item[:type]
      when :setup
        accumulated_sql += item[:sql] + "\n"
        db_dirty = true
        setup_count += 1
      when :query
        # Create db snapshot if state has changed
        if db_dirty || current_db_name.nil?
          db_counter += 1
          current_db_name = "#{basename}-db-#{db_counter}"
          db_path = File.join(@output_dir, "#{current_db_name}.db")
          sql_path = File.join(@output_dir, "#{current_db_name}.sql")
          File.write(sql_path, accumulated_sql)
          unless create_db(accumulated_sql, db_path)
            error_count += 1
            # DB creation failed - skip remaining tests that depend on this state
            db_dirty = false
            current_db_name = nil
            next
          end
          db_dirty = false
        end

        next unless current_db_name # skip if no valid db

        # Skip excluded tests but still accumulate state-modifying SQL
        if @excluded_tests.include?(item[:name])
          if sql_modifies_state?(item[:sql])
            accumulated_sql += item[:sql] + "\n"
            db_dirty = true
          end
          next
        end

        in_file = File.join(@output_dir, "#{item[:name]}.in-sql.txt")
        out_file = File.join(@output_dir, "#{item[:name]}.out-sql.txt")
        formatted_sql = ensure_semicolons(item[:sql]) + "\n"

        File.write(in_file, formatted_sql)

        db_path = File.join(@output_dir, "#{current_db_name}.db")
        output = run_query(db_path, formatted_sql)
        if output.nil?
          error_count += 1
          # Clean up the in file if query fails
          FileUtils.rm_f(in_file)
          next
        end
        File.write(out_file, output)
        manifest[item[:name]] = "#{current_db_name}.db"
        query_count += 1

        # If this query's SQL modifies state, accumulate it
        if sql_modifies_state?(item[:sql])
          accumulated_sql += item[:sql] + "\n"
          db_dirty = true
        end
      end
    end

    return nil if manifest.empty?

    manifest_file = File.join(@output_dir, "#{basename}.manifest.json")
    File.write(manifest_file, JSON.pretty_generate(manifest) + "\n")

    { basename: basename, setup: setup_count, query: query_count, errors: error_count }
  end

  private

  # Detect testprefix from `set ::testprefix NAME` or `set testprefix NAME`
  def detect_testprefix(content, basename)
    if content =~ /^\s*set\s+(?:::)?testprefix\s+(\S+)/
      $1
    else
      nil
    end
  end

  # Parse all extractable items from TCL content.
  # Returns array of {type: :setup|:query, name: String, sql: String}
  def parse_all(content, testprefix)
    items = []
    pos = 0

    while pos < content.length
      # Skip whitespace and comments
      if content[pos] == '#' || (content[pos] == ' ' && lookahead_comment?(content, pos))
        pos = skip_to_next_line(content, pos)
        next
      end

      if content[pos] =~ /\s/
        pos += 1
        next
      end

      # Try do_execsql_test
      if match_at?(content, pos, 'do_execsql_test')
        item, pos = parse_do_execsql_test(content, pos, testprefix)
        items << item if item
      # Try do_test
      elsif match_at?(content, pos, 'do_test')
        item, pos = parse_do_test(content, pos, testprefix)
        items << item if item
      # Try bare execsql at line start
      elsif match_at?(content, pos, 'execsql') && at_line_start?(content, pos)
        item, pos = parse_bare_execsql(content, pos)
        items << item if item
      else
        pos = skip_to_next_line(content, pos)
      end
    end

    items
  end

  # Parse: do_execsql_test NAME { SQL } {EXPECTED}
  def parse_do_execsql_test(content, pos, testprefix)
    # Skip 'do_execsql_test'
    pos += 'do_execsql_test'.length
    pos = skip_whitespace(content, pos)

    # Skip optional flags like -db db2
    while content[pos] == '-'
      pos = skip_word(content, pos) # skip flag
      pos = skip_whitespace(content, pos)
      pos = skip_word(content, pos) # skip flag value
      pos = skip_whitespace(content, pos)
    end

    # Extract test name
    name, pos = extract_word(content, pos)
    return [nil, pos] unless name

    # Replicate TCL's fix_testname: prepend testprefix if name starts with digit
    full_name = (testprefix && name[0] =~ /\d/) ? "#{testprefix}-#{name}" : name

    pos = skip_whitespace(content, pos)

    # Extract SQL body
    sql, pos = extract_braced(content, pos)
    return [nil, pos] unless sql

    pos = skip_whitespace(content, pos)

    # Extract expected output
    expected, pos = extract_braced(content, pos)
    return [nil, pos] unless expected

    sql = sql.strip
    expected = expected.strip

    return [nil, pos] unless valid_sql?(sql)
    return [nil, pos] if regex_expected?(expected)

    if expected.empty?
      [{ type: :setup, name: full_name, sql: ensure_semicolons(sql) }, pos]
    else
      [{ type: :query, name: full_name, sql: sql }, pos]
    end
  end

  # Parse: do_test NAME { BODY } {EXPECTED}
  def parse_do_test(content, pos, testprefix)
    pos += 'do_test'.length
    pos = skip_whitespace(content, pos)

    name, pos = extract_word(content, pos)
    return [nil, pos] unless name

    # Replicate TCL's fix_testname: prepend testprefix if name starts with digit
    name = "#{testprefix}-#{name}" if testprefix && name[0] =~ /\d/

    pos = skip_whitespace(content, pos)

    body, pos = extract_braced(content, pos)
    return [nil, pos] unless body

    pos = skip_whitespace(content, pos)

    expected, pos = extract_braced(content, pos)
    return [nil, pos] unless expected

    expected = expected.strip

    # Try to extract SQL from body
    sql = extract_sql_from_body(body)
    return [nil, pos] unless sql
    return [nil, pos] unless valid_sql?(sql)
    return [nil, pos] if regex_expected?(expected)

    if expected.empty?
      [{ type: :setup, name: name, sql: ensure_semicolons(sql) }, pos]
    else
      [{ type: :query, name: name, sql: sql }, pos]
    end
  end

  # Parse bare: execsql { SQL }
  def parse_bare_execsql(content, pos)
    pos += 'execsql'.length
    pos = skip_whitespace(content, pos)

    return [nil, skip_to_next_line(content, pos)] unless content[pos] == '{'

    sql, pos = extract_braced(content, pos)
    return [nil, pos] unless sql

    sql = sql.strip
    return [nil, pos] unless valid_sql?(sql)

    [{ type: :setup, name: nil, sql: ensure_semicolons(sql) }, pos]
  end

  # Extract SQL from a do_test body.
  # Handles single or multiple execsql/db eval calls.
  def extract_sql_from_body(body)
    body = body.strip
    sql_parts = []
    pos = 0

    while pos < body.length
      # Skip whitespace
      pos += 1 while pos < body.length && body[pos] =~ /\s/
      break if pos >= body.length

      if match_at?(body, pos, 'execsql') || match_at?(body, pos, 'db eval')
        keyword = match_at?(body, pos, 'execsql') ? 'execsql' : 'db eval'
        pos += keyword.length
        pos += 1 while pos < body.length && body[pos] =~ /\s/

        # Must be followed by { (curly-brace SQL, not double-quoted)
        return nil unless body[pos] == '{'

        sql, pos = extract_braced(body, pos)
        return nil unless sql
        sql_parts << sql.strip
      else
        # Body contains something other than execsql/db eval - skip this test
        return nil
      end
    end

    return nil if sql_parts.empty?
    sql_parts.join("\n")
  end

  # Extract balanced braced content starting at pos.
  # Returns [content_string, end_pos] or [nil, pos] on failure.
  def extract_braced(content, pos)
    return [nil, pos] unless pos < content.length && content[pos] == '{'

    depth = 1
    start = pos + 1
    pos += 1

    while depth > 0 && pos < content.length
      case content[pos]
      when '{' then depth += 1
      when '}' then depth -= 1
      end
      pos += 1
    end

    return [nil, pos] if depth != 0
    [content[start..pos - 2], pos]
  end

  def extract_word(content, pos)
    start = pos
    pos += 1 while pos < content.length && content[pos] =~ /\S/
    return [nil, pos] if pos == start
    [content[start..pos - 1], pos]
  end

  def skip_whitespace(content, pos)
    pos += 1 while pos < content.length && content[pos] =~ /[ \t\n\r]/
    pos
  end

  def skip_word(content, pos)
    pos += 1 while pos < content.length && content[pos] =~ /\S/
    pos
  end

  def skip_to_next_line(content, pos)
    idx = content.index("\n", pos)
    idx ? idx + 1 : content.length
  end

  def match_at?(content, pos, word)
    content[pos, word.length] == word
  end

  def at_line_start?(content, pos)
    pos == 0 || content[pos - 1] == "\n"
  end

  def lookahead_comment?(content, pos)
    # Skip spaces to find if we hit a #
    p = pos
    p += 1 while p < content.length && content[p] == ' '
    p < content.length && content[p] == '#'
  end

  def valid_sql?(sql)
    return false if sql.empty?
    # Must contain at least one SQL keyword
    return false unless sql =~ /\b(?:SELECT|INSERT|CREATE|UPDATE|DELETE|DROP|ALTER|BEGIN|COMMIT|ROLLBACK|WITH|PRAGMA|ANALYZE|REINDEX|VACUUM|REPLACE|EXPLAIN)\b/i
    true
  end

  def regex_expected?(expected)
    # TCL regex patterns start with ~/ or /
    expected.start_with?('~/') || expected.start_with?('/')
  end

  def sql_modifies_state?(sql)
    statements = sql.split(';').map(&:strip).reject(&:empty?)
    statements.any? { |s| s !~ /\A\s*(SELECT|EXPLAIN)\b/i }
  end

  def ensure_semicolons(sql)
    statements = sql.split(';').map(&:strip).reject(&:empty?)
    statements.map { |s| "#{s};" }.join("\n")
  end

  def create_db(sql, db_path)
    FileUtils.rm_f(db_path)
    # Ensure sqlite3 always creates the file, even with empty SQL
    effective_sql = sql.strip.empty? ? "SELECT 1;\n" : sql
    IO.popen([SQLITE3_BIN, db_path], 'r+', err: [:child, :out]) do |io|
      io.write(effective_sql)
      io.close_write
      io.read
    end
    $?.success? && File.exist?(db_path)
  end

  def run_query(db_path, sql)
    tmpfile = Tempfile.new(['query', '.db'])
    tmpfile.close
    FileUtils.cp(db_path, tmpfile.path)

    output = IO.popen([SQLITE3_BIN, tmpfile.path], 'r+', err: '/dev/null') do |io|
      io.write(sql)
      io.close_write
      io.read
    end

    tmpfile.unlink

    return nil unless $?.success?
    output
  end
end

if __FILE__ == $0
  require 'optparse'

  excluded_tests = []
  args = ARGV.dup

  # Parse --exclude flags before positional args
  parser = OptionParser.new do |opts|
    opts.on('--exclude TEST_NAME', 'Exclude a specific test name from generation') do |name|
      excluded_tests << name
    end
  end
  parser.order!(args)

  test_dir = args[0] || File.expand_path('../../sqlite-c/test', __dir__)
  output_dir = args[1] || File.expand_path('../test-c', __dir__)

  unless File.exist?(TclTestExtractor::SQLITE3_BIN)
    puts "ERROR: sqlite3 binary not found at #{TclTestExtractor::SQLITE3_BIN}"
    exit 1
  end

  extractor = TclTestExtractor.new(output_dir, excluded_tests: excluded_tests)

  if File.file?(test_dir)
    # Single file mode
    stats = extractor.extract(test_dir)
    if stats
      puts "#{stats[:basename]}: #{stats[:query]} queries, #{stats[:setup]} setups, #{stats[:errors]} errors"
    else
      puts "#{File.basename(test_dir)}: no extractable tests"
    end
  else
    # Directory mode - process all .test files
    test_files = Dir.glob(File.join(test_dir, '*.test')).sort
    puts "Processing #{test_files.length} test files..."

    total_query = 0
    total_setup = 0
    total_errors = 0
    total_files = 0

    test_files.each do |tcl_file|
      stats = extractor.extract(tcl_file)
      next unless stats

      total_files += 1
      total_query += stats[:query]
      total_setup += stats[:setup]
      total_errors += stats[:errors]

      if stats[:errors] > 0
        puts "  #{stats[:basename]}: #{stats[:query]} queries, #{stats[:setup]} setups, #{stats[:errors]} errors"
      end
    end

    puts "\nDone: #{total_files} files, #{total_query} queries, #{total_setup} setups, #{total_errors} errors"
    puts "Skipped #{test_files.length - total_files} files (no extractable tests)"
  end
end
