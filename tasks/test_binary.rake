# frozen_string_literal: true

desc 'Run binary parity tests against C sqlite3 reference output'
task :test_binary do
  require_relative '../lib/sqlite_purerb'

  test_dir = File.expand_path('../test-binary', __dir__)
  input_files = Dir.glob(File.join(test_dir, '*.c-input.txt')).sort
  pass_count = 0
  fail_count = 0

  input_files.each do |input_file|
    base = input_file.sub(/\.c-input\.txt\z/, '')
    db_file = "#{base}.sqlite3"
    expected_file = "#{base}.c-output.txt"
    name = File.basename(base)

    unless File.exist?(db_file)
      puts "SKIP #{name}: database file not found"
      next
    end

    unless File.exist?(expected_file)
      puts "SKIP #{name}: expected output file not found"
      next
    end

    input_text = File.read(input_file)
    expected = File.read(expected_file)

    repl = SqlitePurerb::REPL.new(db_file)
    actual = repl.process(input_text)
    repl.close

    # Compare line by line, stripping trailing whitespace
    expected_lines = expected.lines.map(&:rstrip)
    actual_lines = actual.lines.map(&:rstrip)

    # Remove trailing empty lines
    expected_lines.pop while expected_lines.last&.empty?
    actual_lines.pop while actual_lines.last&.empty?

    if expected_lines == actual_lines
      puts "PASS #{name}"
      pass_count += 1
    else
      puts "FAIL #{name}"
      fail_count += 1

      # Show diff
      max_lines = [expected_lines.length, actual_lines.length].max
      max_lines.times do |i|
        exp = expected_lines[i] || '(missing)'
        act = actual_lines[i] || '(missing)'
        next if exp == act

        puts "  line #{i + 1}:"
        puts "    expected: #{exp.inspect}"
        puts "    actual:   #{act.inspect}"
        break if i > 10 # Limit output
      end
    end
  end

  puts "\n#{pass_count + fail_count} test(s): #{pass_count} passed, #{fail_count} failed"
  exit 1 if fail_count > 0
end
