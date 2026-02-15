# frozen_string_literal: true

module SqlitePurerb
  # Pager handles reading pages from the SQLite database file
  class Pager
    HEADER_SIZE = 100
    MAGIC_STRING = "SQLite format 3\x00"

    attr_reader :page_size, :page_count, :text_encoding, :schema_cookie

    def initialize(file_path)
      @file = File.open(file_path, 'rb')
      read_header
    end

    def close
      @file.close
    end

    # Read a page by number (1-indexed)
    def read_page(page_num)
      raise "Invalid page number: #{page_num}" if page_num < 1 || page_num > @page_count

      offset = (page_num - 1) * @page_size
      @file.seek(offset)
      @file.read(@page_size)
    end

    private

    def read_header
      @file.seek(0)
      header = @file.read(HEADER_SIZE)

      magic = header[0, 16]
      raise "Not a SQLite database file" unless magic == MAGIC_STRING

      # Page size (bytes 16-17, big-endian)
      # Value of 1 means 65536
      raw_page_size = read_be16(header, 16)
      @page_size = raw_page_size == 1 ? 65536 : raw_page_size

      # Database size in pages (bytes 28-31, big-endian)
      @page_count = read_be32(header, 28)

      # If page_count is 0, calculate from file size
      if @page_count == 0
        @file.seek(0, IO::SEEK_END)
        file_size = @file.tell
        @page_count = file_size / @page_size
      end

      # Schema cookie (bytes 40-43, big-endian)
      # Incremented each time the schema changes (CREATE/DROP TABLE/INDEX)
      @schema_cookie = read_be32(header, 40)

      # Text encoding (bytes 56-59)
      # 1 = UTF-8, 2 = UTF-16LE, 3 = UTF-16BE
      @text_encoding = read_be32(header, 56)
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
  end
end
