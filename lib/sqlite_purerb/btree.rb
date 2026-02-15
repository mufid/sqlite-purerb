# frozen_string_literal: true

module SqlitePurerb
  # BTree handles B-tree page traversal and cell parsing
  class BTree
    # Page type flags
    PTF_INTKEY = 0x01    # Table B-tree (rowid as key)
    PTF_ZERODATA = 0x02  # Index B-tree
    PTF_LEAFDATA = 0x04  # Legacy
    PTF_LEAF = 0x08      # Leaf node

    attr_reader :pager

    def initialize(pager)
      @pager = pager
    end

    # Scan all rows from a table starting at root_page
    # Yields [rowid, values_array] for each row
    def scan_table(root_page, &block)
      return enum_for(:scan_table, root_page) unless block_given?

      scan_page(root_page, &block)
    end

    private

    def scan_page(page_num, &block)
      page_data = @pager.read_page(page_num)

      # Determine header offset (page 1 has 100-byte file header)
      header_offset = page_num == 1 ? 100 : 0

      # Parse page header
      flags = page_data.getbyte(header_offset)
      cell_count = read_be16(page_data, header_offset + 3)

      is_leaf = (flags & PTF_LEAF) != 0
      is_table = (flags & PTF_INTKEY) != 0

      unless is_table
        raise "Expected table B-tree but got index B-tree"
      end

      # Cell pointer array starts after header
      # Leaf pages have 8-byte header, internal pages have 12-byte header
      cell_ptr_offset = header_offset + (is_leaf ? 8 : 12)

      if is_leaf
        # Leaf page: parse all cells and yield rows
        cell_count.times do |i|
          cell_offset = read_be16(page_data, cell_ptr_offset + i * 2)
          rowid, values = parse_table_leaf_cell(page_data, cell_offset)
          block.call(rowid, values)
        end
      else
        # Internal page: recursively scan child pages
        # First, scan leftmost children
        cell_count.times do |i|
          cell_offset = read_be16(page_data, cell_ptr_offset + i * 2)
          left_child = read_be32(page_data, cell_offset)
          scan_page(left_child, &block)
        end

        # Then scan the rightmost child (from page header)
        right_child = read_be32(page_data, header_offset + 8)
        scan_page(right_child, &block)
      end
    end

    # Parse a table leaf cell (INTKEY table, leaf node)
    # Format: varint(payload_size), varint(rowid), payload
    # Handles overflow pages when payload exceeds local storage
    def parse_table_leaf_cell(page_data, offset, page_num = nil)
      pos = offset

      # Read payload size
      payload_size, bytes_read = read_varint(page_data, pos)
      pos += bytes_read

      # Read rowid
      rowid, bytes_read = read_varint(page_data, pos)
      pos += bytes_read

      # Calculate local payload size
      # SQLite stores some payload locally and rest on overflow pages
      usable_size = @pager.page_size
      max_local = calculate_max_local(usable_size)
      min_local = calculate_min_local(usable_size)

      if payload_size <= max_local
        # All payload fits on this page
        local_size = payload_size
        overflow_page = 0
      else
        # Some payload is on overflow pages
        # Local size is calculated to leave room for overflow page pointer (4 bytes)
        surplus = min_local + (payload_size - min_local) % (usable_size - 4)
        local_size = surplus <= max_local ? surplus : min_local
        # Last 4 bytes of local area contain overflow page number
        overflow_page = read_be32(page_data, pos + local_size)
      end

      # Read local payload
      payload = page_data[pos, local_size].dup
      payload.force_encoding('BINARY')

      # Read overflow pages if needed
      remaining = payload_size - local_size
      current_overflow = overflow_page

      while remaining > 0 && current_overflow != 0
        overflow_data = @pager.read_page(current_overflow)

        # First 4 bytes are next overflow page pointer
        next_overflow = read_be32(overflow_data, 0)

        # Rest is payload data (up to usable_size - 4)
        chunk_size = [remaining, usable_size - 4].min
        payload << overflow_data[4, chunk_size]

        remaining -= chunk_size
        current_overflow = next_overflow
      end

      # Decode the record
      values = decode_record(payload)

      [rowid, values]
    end

    # Calculate maximum local payload for table leaf cells (LEAFDATA trees)
    def calculate_max_local(usable_size)
      usable_size - 35
    end

    # Calculate minimum local payload for table leaf cells (LEAFDATA trees)
    def calculate_min_local(usable_size)
      ((usable_size - 12) * 32 / 255) - 23
    end

    # Decode a SQLite record format
    # Format: varint(header_size), varint(type0), varint(type1), ..., data0, data1, ...
    def decode_record(payload)
      pos = 0

      # Read header size
      header_size, bytes_read = read_varint(payload, pos)
      pos += bytes_read

      # Read serial types until we reach header_size
      serial_types = []
      while pos < header_size
        serial_type, bytes_read = read_varint(payload, pos)
        pos += bytes_read
        serial_types << serial_type
      end

      # Now pos should equal header_size, data starts here
      data_pos = header_size
      values = []

      serial_types.each do |serial_type|
        value, size = decode_value(payload, data_pos, serial_type)
        values << value
        data_pos += size
      end

      values
    end

    # Decode a value based on serial type
    def decode_value(data, offset, serial_type)
      case serial_type
      when 0
        # NULL
        [nil, 0]
      when 1
        # 1-byte signed integer
        val = data.getbyte(offset)
        val = val - 256 if val >= 128
        [val, 1]
      when 2
        # 2-byte signed integer (big-endian)
        val = read_be16(data, offset)
        val = val - 65536 if val >= 32768
        [val, 2]
      when 3
        # 3-byte signed integer (big-endian)
        val = (data.getbyte(offset) << 16) |
              (data.getbyte(offset + 1) << 8) |
              data.getbyte(offset + 2)
        val = val - (1 << 24) if val >= (1 << 23)
        [val, 3]
      when 4
        # 4-byte signed integer (big-endian)
        val = read_be32(data, offset)
        val = val - (1 << 32) if val >= (1 << 31)
        [val, 4]
      when 5
        # 6-byte signed integer (big-endian)
        val = read_be48(data, offset)
        val = val - (1 << 48) if val >= (1 << 47)
        [val, 6]
      when 6
        # 8-byte signed integer (big-endian)
        val = read_be64(data, offset)
        val = val - (1 << 64) if val >= (1 << 63)
        [val, 8]
      when 7
        # 8-byte IEEE 754 double (big-endian)
        bytes = data[offset, 8]
        val = bytes.unpack1('G')  # Big-endian double
        [val, 8]
      when 8
        # Integer constant 0
        [0, 0]
      when 9
        # Integer constant 1
        [1, 0]
      when 10, 11
        # Reserved
        raise "Reserved serial type: #{serial_type}"
      else
        if serial_type >= 12 && serial_type.even?
          # BLOB: length = (N-12)/2
          length = (serial_type - 12) / 2
          [data[offset, length], length]
        elsif serial_type >= 13 && serial_type.odd?
          # TEXT: length = (N-13)/2
          length = (serial_type - 13) / 2
          text = data[offset, length]
          # Assume UTF-8 encoding for simplicity
          text = text.force_encoding('UTF-8')
          [text, length]
        else
          raise "Unknown serial type: #{serial_type}"
        end
      end
    end

    # Read a varint from data at offset
    # SQLite uses big-endian varint: high bits come from earlier bytes
    # Returns [value, bytes_consumed]
    def read_varint(data, offset)
      value = 0
      bytes_read = 0

      9.times do |i|
        byte = data.getbyte(offset + i)
        return [value, bytes_read] if byte.nil?
        bytes_read += 1

        if i < 8
          # Shift existing value left and add new 7 bits
          value = (value << 7) | (byte & 0x7F)
          return [value, bytes_read] if (byte & 0x80) == 0
        else
          # 9th byte: shift left 8 and use all 8 bits
          value = (value << 8) | byte
          return [value, bytes_read]
        end
      end

      [value, bytes_read]
    end

    def read_be16(data, offset)
      (data.getbyte(offset) << 8) | data.getbyte(offset + 1)
    end

    def read_be32(data, offset)
      (data.getbyte(offset) << 24) |
        (data.getbyte(offset + 1) << 16) |
        (data.getbyte(offset + 2) << 8) |
        data.getbyte(offset + 3)
    end

    def read_be48(data, offset)
      (data.getbyte(offset) << 40) |
        (data.getbyte(offset + 1) << 32) |
        (data.getbyte(offset + 2) << 24) |
        (data.getbyte(offset + 3) << 16) |
        (data.getbyte(offset + 4) << 8) |
        data.getbyte(offset + 5)
    end

    def read_be64(data, offset)
      (data.getbyte(offset) << 56) |
        (data.getbyte(offset + 1) << 48) |
        (data.getbyte(offset + 2) << 40) |
        (data.getbyte(offset + 3) << 32) |
        (data.getbyte(offset + 4) << 24) |
        (data.getbyte(offset + 5) << 16) |
        (data.getbyte(offset + 6) << 8) |
        data.getbyte(offset + 7)
    end
  end
end
