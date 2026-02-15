namespace :lemonrb do
  desc "Generate parserb.rb from parserb.y using Lemonrb"
  task :generate do
    # Only require what's needed for generation (not the generated parserb.rb)
    require_relative '../lib/sqlite_purerb/lemonrb'

    grammar_dir = File.expand_path('../grammars', __dir__)
    lib_dir = File.expand_path('../lib/sqlite_purerb', __dir__)

    grammar_path = File.join(grammar_dir, 'parserb.y')
    output_path = File.join(lib_dir, 'parserb.rb')

    unless File.exist?(grammar_path)
      abort "Grammar file not found: #{grammar_path}"
    end

    content = File.read(grammar_path)

    puts "Processing grammar: #{grammar_path}"
    lemon = SqlitePurerb::Lemonrb.new
    lemon.process(content)

    puts "  Symbols: #{lemon.symbols.count}"
    puts "  Rules: #{lemon.rules.count}"
    puts "  States: #{lemon.states.count}"

    code = lemon.generate_ruby_parser(output_path)

    puts "Generated: #{output_path}"
    puts "  Lines: #{code.lines.count}"
  end
end
