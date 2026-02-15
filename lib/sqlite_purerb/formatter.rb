# frozen_string_literal: true

module SqlitePurerb
  # Formatter produces text output matching C sqlite3's formatting.
  #
  # Supports:
  # - List mode (pipe-separated) for SELECT results
  # - Column mode (fixed-width) for EXPLAIN results
  #   EXPLAIN always uses column mode regardless of current mode setting,
  #   matching C sqlite3's behavior.
  class Formatter
    attr_accessor :mode, :headers, :separator

    # Fixed column widths for EXPLAIN output (matches C sqlite3)
    EXPLAIN_WIDTHS = [4, 13, 4, 4, 4, 13, 2, 13].freeze
    EXPLAIN_HEADERS = %w[addr opcode p1 p2 p3 p4 p5 comment].freeze

    def initialize
      @mode = :list
      @headers = false
      @separator = '|'
    end

    # Format SELECT result rows
    def format_rows(column_names, rows)
      case @mode
      when :list then format_rows_list(column_names, rows)
      else format_rows_list(column_names, rows)
      end
    end

    # Format EXPLAIN output (always column mode, matching C sqlite3)
    def format_explain(program)
      format_explain_column(program)
    end

    private

    # --- List mode ---

    def format_rows_list(column_names, rows)
      lines = []
      lines << column_names.join(@separator) if @headers
      rows.each do |row|
        values = column_names.map { |c| format_value(row[c]) }
        lines << values.join(@separator)
      end
      lines.join("\n")
    end

    # --- Column mode (EXPLAIN) ---

    def format_explain_column(program)
      widths = EXPLAIN_WIDTHS
      gap = '  '

      # Determine loop body range for indentation (between Rewind+1 and Next-1)
      indent_range = find_loop_body_range(program)

      lines = []

      # Header
      header_parts = EXPLAIN_HEADERS[0..5].each_with_index.map { |h, i| h.ljust(widths[i]) }
      header_line = header_parts.join(gap) + gap +
                    EXPLAIN_HEADERS[6].ljust(widths[6] + gap.length) +
                    EXPLAIN_HEADERS[7].ljust(widths[7])
      lines << header_line

      # Separator
      sep_parts = widths[0..5].map { |w| '-' * w }
      sep_line = sep_parts.join(gap) + gap +
                 ('-' * widths[6]).ljust(widths[6] + gap.length) +
                 ('-' * widths[7])
      lines << sep_line

      # Instructions
      program.instructions.each_with_index do |instr, addr|
        name = VDBE::OP::NAMES[instr.opcode] || "unknown(#{instr.opcode})"
        p4_str = instr.p4.nil? ? '' : instr.p4.to_s
        p5_val = instr.p5 || 0
        comment = instr.comment || ''

        # C sqlite3 indents loop body by shifting the line right by 2 spaces
        # (inserted between addr gap and opcode field)
        in_loop = if indent_range.is_a?(Array)
                    indent_range.any? { |r| r.include?(addr) }
                  elsif indent_range
                    indent_range.include?(addr)
                  else
                    false
                  end
        indent = in_loop ? '  ' : ''

        main_fields = [
          addr.to_s.ljust(widths[0]),
          name.ljust(widths[1]),
          instr.p1.to_s.ljust(widths[2]),
          instr.p2.to_s.ljust(widths[3]),
          instr.p3.to_s.ljust(widths[4]),
          p4_str.ljust(widths[5])
        ]

        # p5 absorbs the following gap so overflow eats gap instead of adding extra space
        p5_str = p5_val.to_s.ljust(widths[6] + gap.length)

        line = main_fields[0] + gap + indent +
               main_fields[1..].join(gap) + gap +
               p5_str + comment
        lines << line
      end

      lines.join("\n")
    end

    # Find all loop body ranges for indentation
    # Handles Rewind/Next, SeekGE/Next, SorterSort/SorterNext, and Sort/Next loops
    def find_loop_body_range(program)
      ranges = []

      # Find Rewind -> first Next pair
      rewind_addr = nil
      program.instructions.each_with_index do |instr, addr|
        if instr.opcode == VDBE::OP::REWIND
          rewind_addr = addr
        elsif instr.opcode == VDBE::OP::NEXT && rewind_addr
          ranges << (rewind_addr + 1...addr)
          rewind_addr = nil
          break  # Only first Rewind/Next pair for the main scan loop
        end
      end

      # Find SeekGE -> Next pair (index scan loop)
      seek_addr = nil
      program.instructions.each_with_index do |instr, addr|
        if instr.opcode == VDBE::OP::SEEK_GE
          seek_addr = addr
        elsif instr.opcode == VDBE::OP::NEXT && seek_addr
          ranges << (seek_addr + 1...addr)
          seek_addr = nil
          break
        end
      end

      # Find SorterSort -> SorterNext pair
      sorter_sort_addr = nil
      program.instructions.each_with_index do |instr, addr|
        if instr.opcode == VDBE::OP::SORTER_SORT
          sorter_sort_addr = addr
        elsif instr.opcode == VDBE::OP::SORTER_NEXT && sorter_sort_addr
          ranges << (sorter_sort_addr + 1...addr)
          sorter_sort_addr = nil
        end
      end

      # Find Sort -> Next pair (for ephemeral table output)
      sort_addr = nil
      program.instructions.each_with_index do |instr, addr|
        if instr.opcode == VDBE::OP::SORT
          sort_addr = addr
        elsif instr.opcode == VDBE::OP::NEXT && sort_addr
          ranges << (sort_addr + 1...addr)
          sort_addr = nil
        end
      end

      return nil if ranges.empty?

      # Combine all ranges
      ranges
    end

    # --- Value formatting ---

    def format_value(val)
      case val
      when nil then ''
      when Float then format_float(val)
      else val.to_s
      end
    end

    # Format float to match C sqlite3's %!.15g behavior
    def format_float(val)
      formatted = sprintf('%.15g', val)

      # Ensure decimal point is present (the '!' flag in C's %!.15g)
      unless formatted.include?('.') || formatted.include?('e') || formatted.include?('E')
        formatted += '.0'
      end

      formatted
    end
  end
end
