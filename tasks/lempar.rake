namespace :lempar do
  LEMPAR_C = File.expand_path('../../sqlite-c/tool/lempar.c', __dir__)

  desc "Strip comments and show lempar.c structure"
  task :analyze do
    unless File.exist?(LEMPAR_C)
      abort "Source file not found: #{LEMPAR_C}"
    end

    content = File.read(LEMPAR_C)

    # Remove multi-line comments
    content = content.gsub(%r{/\*.*?\*/}m, '')

    # Remove single-line comments
    content = content.gsub(%r{//.*$}, '')

    # Remove empty lines
    lines = content.lines.map(&:rstrip).reject(&:empty?)

    # Track ifdef blocks
    ifdef_stack = []
    current_block = nil

    lines.each_with_index do |line, idx|
      case line
      when /^#\s*if(?:def|ndef)?\s+(.+)/
        ifdef_stack.push($1.strip)
        puts "#{idx + 1}: >>> #ifdef #{ifdef_stack.last}"
      when /^#\s*else/
        puts "#{idx + 1}: === #else (was: #{ifdef_stack.last})"
      when /^#\s*endif/
        cond = ifdef_stack.pop
        puts "#{idx + 1}: <<< #endif #{cond}"
      when /^%%/
        puts "#{idx + 1}: %%%% TEMPLATE INSERTION POINT %%%%"
      when /^(void|int|static)\s+\w+\s*\(/
        puts "#{idx + 1}: FUNCTION: #{line[0..60]}..."
      end
    end

    puts "\n=== Summary ==="
    puts "Total lines (stripped): #{lines.count}"
    puts "Template markers (%%): #{lines.count { |l| l.start_with?('%%') }}"
  end

  desc "Extract core parser logic (no comments, simplified ifdefs)"
  task :extract do
    unless File.exist?(LEMPAR_C)
      abort "Source file not found: #{LEMPAR_C}"
    end

    content = File.read(LEMPAR_C)

    # Remove multi-line comments
    content = content.gsub(%r{/\*.*?\*/}m, '')

    # Remove single-line comments
    content = content.gsub(%r{//.*$}, '')

    # Process lines
    lines = content.lines
    output = []
    skip_depth = 0
    ifdef_stack = []

    # Define which ifdef branches to keep (first/if branch by default)
    # Set to true to keep #else branch instead
    prefer_else = {
      'YYERRORSYMBOL' => false,        # Keep error symbol handling
      'YYTRACKMAXSTACKDEPTH' => false, # Skip tracking
      'NDEBUG' => true,                # Skip debug code (keep else/nothing)
      'YYNOERRORRECOVERY' => false,    # Keep error recovery
      'YYFALLBACK' => true,            # Keep fallback
      'YYWILDCARD' => true,            # Keep wildcard
      'INTERFACE' => false,
    }

    lines.each do |line|
      stripped = line.strip

      case stripped
      when /^#\s*if(?:def)?\s+(.+)/
        cond = $1.strip
        ifdef_stack.push({ cond: cond, in_else: false, keep: !prefer_else[cond] })
        if !ifdef_stack.last[:keep]
          skip_depth += 1
        end
      when /^#\s*ifndef\s+(.+)/
        cond = $1.strip
        ifdef_stack.push({ cond: cond, in_else: false, keep: prefer_else[cond] != false })
        if !ifdef_stack.last[:keep]
          skip_depth += 1
        end
      when /^#\s*else/
        if ifdef_stack.any?
          was_keeping = ifdef_stack.last[:keep]
          ifdef_stack.last[:in_else] = true
          ifdef_stack.last[:keep] = !was_keeping
          if was_keeping
            skip_depth += 1
          else
            skip_depth -= 1
          end
        end
      when /^#\s*endif/
        if ifdef_stack.any?
          if ifdef_stack.last[:keep] && !ifdef_stack.last[:in_else]
            # Was keeping if-branch, nothing to adjust
          elsif ifdef_stack.last[:keep] && ifdef_stack.last[:in_else]
            # Was keeping else-branch, nothing to adjust
          else
            skip_depth -= 1 if skip_depth > 0
          end
          ifdef_stack.pop
        end
      when /^#\s*(define|include|undef)/
        output << line if skip_depth == 0
      when /^%%/
        output << line if skip_depth == 0
      else
        output << line if skip_depth == 0 && !stripped.empty?
      end
    end

    result = output.join
    puts result
    puts "\n// Extracted #{output.count} lines"
  end
end
