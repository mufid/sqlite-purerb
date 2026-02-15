# frozen_string_literal: true

SQLITE3_BIN = File.expand_path('../../sqlite-c/bld/sqlite3', __dir__)
TCL_TEST_DIR = File.expand_path('../../sqlite-c/test', __dir__)
TEST_C_DIR = File.expand_path('../test-c', __dir__)
EXTRACT_SCRIPT = File.expand_path('../scripts/extract_tcl_tests.rb', __dir__)

# Tests that produce non-deterministic output (time-dependent, randomblob, system-dependent)
EXCLUDED_TESTS = %w[
  attach-1.3
  e_expr-12.2.6
  e_expr-12.2.8
  pragma2-2.1
  zipfile-1.2
  zipfile-1.4
  zipfile-1.6.1
  zipfile-2.1
  zipfile-2.2
  zipfile-2.4
].freeze

desc 'Generate test-c/ files from all TCL test files'
task :test_c_generate do
  cmd = ['ruby', EXTRACT_SCRIPT]
  EXCLUDED_TESTS.each { |t| cmd.push('--exclude', t) }
  cmd.push(TCL_TEST_DIR, TEST_C_DIR)
  system(*cmd, exception: true)
end

# Filter manifests by TESTNAME env var.
# TESTNAME=boundary4 -> only boundary4.manifest.json
def filtered_manifests
  manifests = Dir.glob(File.join(TEST_C_DIR, '*.manifest.json')).sort
  if manifests.empty?
    puts "No manifests found in #{TEST_C_DIR}. Run `rake test_c_generate` first."
    exit 1
  end

  if (filter = ENV['TESTNAME'])
    manifests.select! { |m| File.basename(m, '.manifest.json') == filter }
    if manifests.empty?
      puts "No manifest found for TESTNAME=#{filter}"
      exit 1
    end
  end

  manifests
end

desc 'Run test-c/ queries against C sqlite3 (validates extraction). TESTNAME=file to filter.'
task :test_c_c do
  require 'json'
  require 'fileutils'
  require 'tempfile'

  pass_count = 0
  fail_count = 0

  filtered_manifests.each do |manifest_file|
    manifest = JSON.parse(File.read(manifest_file))

    manifest.each do |test_name, db_name|
      in_file = File.join(TEST_C_DIR, "#{test_name}.in-sql.txt")
      out_file = File.join(TEST_C_DIR, "#{test_name}.out-sql.txt")
      db_file = File.join(TEST_C_DIR, db_name)

      unless File.exist?(in_file) && File.exist?(out_file) && File.exist?(db_file)
        puts "SKIP #{test_name}: missing files"
        next
      end

      expected = File.binread(out_file).force_encoding('UTF-8')
      input_sql = File.binread(in_file).force_encoding('UTF-8')

      tmpfile = Tempfile.new(['test_c', '.db'])
      tmpfile.close
      FileUtils.cp(db_file, tmpfile.path)

      actual = IO.popen([SQLITE3_BIN, tmpfile.path], 'r+') do |io|
        io.write(input_sql)
        io.close_write
        io.read
      end

      tmpfile.unlink

      actual = actual.force_encoding('UTF-8') if actual
      expected_lines = expected.scrub.lines.map(&:rstrip)
      actual_lines = (actual || '').scrub.lines.map(&:rstrip)
      expected_lines.pop while expected_lines.last&.empty?
      actual_lines.pop while actual_lines.last&.empty?

      if expected_lines == actual_lines
        puts "PASS #{test_name}"
        pass_count += 1
      else
        puts "FAIL #{test_name}"
        fail_count += 1
        max_lines = [expected_lines.length, actual_lines.length].max
        max_lines.times do |i|
          exp = expected_lines[i] || '(missing)'
          act = actual_lines[i] || '(missing)'
          next if exp == act

          puts "  line #{i + 1}:"
          puts "    expected: #{exp.inspect}"
          puts "    actual:   #{act.inspect}"
          break if i > 10
        end
      end
    end
  end

  puts "\n#{pass_count + fail_count} test(s): #{pass_count} passed, #{fail_count} failed"
  exit 1 if fail_count > 0
end

desc 'Run test-c/ queries against sqlite-purerb REPL. TESTNAME=file to filter. FAILFAST=yes to stop on first failure.'
task :test_c_rb do
  require 'json'
  require 'fileutils'
  require 'tempfile'
  require_relative '../lib/sqlite_purerb'

  failfast = ENV['FAILFAST']&.downcase == 'yes'
  pass_count = 0
  fail_count = 0

  catch(:done) do
    filtered_manifests.each do |manifest_file|
      manifest = JSON.parse(File.read(manifest_file))

      manifest.each do |test_name, db_name|
        in_file = File.join(TEST_C_DIR, "#{test_name}.in-sql.txt")
        out_file = File.join(TEST_C_DIR, "#{test_name}.out-sql.txt")
        db_file = File.join(TEST_C_DIR, db_name)

        unless File.exist?(in_file) && File.exist?(out_file) && File.exist?(db_file)
          puts "SKIP #{test_name}: missing files"
          next
        end

        expected = File.binread(out_file).force_encoding('UTF-8')
        input_sql = File.binread(in_file).force_encoding('UTF-8')

        tmpfile = Tempfile.new(['test_c_rb', '.db'])
        tmpfile.close
        FileUtils.cp(db_file, tmpfile.path)

        begin
          repl = SqlitePurerb::REPL.new(tmpfile.path)
          actual = repl.process(input_sql)
          repl.close
        rescue => e
          puts "FAIL #{test_name} (error: #{e.message})"
          fail_count += 1
          tmpfile.unlink
          throw(:done) if failfast
          next
        end

        tmpfile.unlink

        expected_lines = expected.scrub.lines.map(&:rstrip)
        actual_lines = actual.scrub.lines.map(&:rstrip)
        expected_lines.pop while expected_lines.last&.empty?
        actual_lines.pop while actual_lines.last&.empty?

        if expected_lines == actual_lines
          puts "PASS #{test_name}"
          pass_count += 1
        else
          puts "FAIL #{test_name}"
          fail_count += 1
          max_lines = [expected_lines.length, actual_lines.length].max
          max_lines.times do |i|
            exp = expected_lines[i] || '(missing)'
            act = actual_lines[i] || '(missing)'
            next if exp == act

            puts "  line #{i + 1}:"
            puts "    expected: #{exp.inspect}"
            puts "    actual:   #{act.inspect}"
            break if i > 10
          end
          throw(:done) if failfast
        end
      end
    end
  end

  puts "\n#{pass_count + fail_count} test(s): #{pass_count} passed, #{fail_count} failed"
  exit 1 if fail_count > 0
end
