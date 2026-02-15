# frozen_string_literal: true

require_relative 'sqlite_purerb/version'
require_relative 'sqlite_purerb/token'
require_relative 'sqlite_purerb/prepare'
require_relative 'sqlite_purerb/lemonrb'
require_relative 'sqlite_purerb/parserb'
require_relative 'sqlite_purerb/tokenizer'
require_relative 'sqlite_purerb/pager'
require_relative 'sqlite_purerb/btree'
require_relative 'sqlite_purerb/ast'
require_relative 'sqlite_purerb/query_parser'
require_relative 'sqlite_purerb/vdbe'
require_relative 'sqlite_purerb/vdbes/execution_context'
Dir[File.join(__dir__, 'sqlite_purerb', 'vdbes', '*.rb')].sort.each do |f|
  next if f.end_with?('execution_context.rb', 'dispatch.rb')
  require f
end
Dir[File.join(__dir__, 'sqlite_purerb', 'vdbes', '{read,write}', '*.rb')].each { |f| require f }
require_relative 'sqlite_purerb/vdbes/dispatch'
Dir[File.join(__dir__, 'sqlite_purerb', 'code_generators', '*.rb')].each { |f| require f }
require_relative 'sqlite_purerb/code_generator'
require_relative 'sqlite_purerb/executor'
require_relative 'sqlite_purerb/database'
require_relative 'sqlite_purerb/formatter'
require_relative 'sqlite_purerb/repl'

module SqlitePurerb
end
