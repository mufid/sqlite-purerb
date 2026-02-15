class LemonParser
rule
  grammar       : items                               { result = val[0] }

  items         :                                     { result = [] }
                | items item                          { result = val[0] << val[1] if val[1]; result ||= val[0] }

  item          : directive
                | rule
                | conditional
                | COMMENT                             { result = [:comment, val[0]] }

  # List directives: %token ..., %left ..., %fallback ID ...
  directive     : PERCENT LIST_DIR token_list DOT     { result = [:directive_list, val[1], val[2]] }
                | PERCENT FALLBACK IDENT token_list DOT
                                                      { result = [:fallback, val[2], val[3]] }
                | PERCENT WILDCARD IDENT DOT          { result = [:wildcard, val[2]] }
  # Block directives: %include {...}, %destructor IDENT {...}
                | PERCENT BLOCK_DIR BRACED            { result = [:directive_block, val[1], val[2]] }
                | PERCENT DESTRUCTOR IDENT BRACED     { result = [:destructor, val[2], val[3]] }
  # Typed directives: %type IDENT {...}, %token_type {...}
                | PERCENT TYPE_DIR BRACED             { result = [:directive_typed, val[1], nil, val[2]] }
                | PERCENT TYPE_DIR IDENT BRACED       { result = [:directive_typed, val[1], val[2], val[3]] }
  # Simple directives: %name foo
                | PERCENT IDENT                       { result = [:directive, val[1], nil] }
                | PERCENT IDENT IDENT                 { result = [:directive, val[1], val[2]] }
                | PERCENT IDENT NUMBER                { result = [:directive, val[1], val[2]] }

  token_list    : IDENT                               { result = [val[0]] }
                | token_list IDENT                    { result = val[0] << val[1] }
                | token_list PIPE IDENT               { result = val[0] << val[2] }
                | token_list conditional              { result = val[0] << val[1] }
                | token_list COMMENT                  { result = val[0] }

  conditional   : PERCENT IFDEF cond_expr             { result = [:ifdef, val[1], val[2]] }
                | PERCENT ELSE                        { result = [:else] }
                | PERCENT ENDIF                       { result = [:endif] }
                | PERCENT ENDIF cond_term             { result = [:endif, val[2]] }

  cond_expr     : cond_term                           { result = val[0] }
                | cond_expr DPIPE cond_term           { result = "#{val[0]} || #{val[2]}" }
                | cond_expr DAMP cond_term            { result = "#{val[0]} && #{val[2]}" }

  cond_term     : IDENT                               { result = val[0] }
                | BANG IDENT                          { result = "!#{val[1]}" }

  rule          : lhs ASSIGN rhs_list DOT             { result = [:rule, val[0], val[2], nil] }
                | lhs ASSIGN rhs_list DOT BRACED      { result = [:rule, val[0], val[2], val[4]] }
                | lhs ASSIGN rhs_list DOT LBRACKET IDENT RBRACKET
                                                      { result = [:rule, val[0], val[2], nil, val[5]] }
                | lhs ASSIGN rhs_list DOT LBRACKET IDENT RBRACKET BRACED
                                                      { result = [:rule, val[0], val[2], val[7], val[5]] }

  lhs           : IDENT                               { result = [val[0], nil] }
                | IDENT LPAREN IDENT RPAREN           { result = [val[0], val[2]] }

  rhs_list      :                                     { result = [] }
                | rhs_list rhs_item                   { result = val[0] << val[1] }

  rhs_item      : simple_item                         { result = val[0] }
                | alt_sequence                        { result = val[0] }

  simple_item   : IDENT                               { result = [val[0], nil] }
                | IDENT LPAREN IDENT RPAREN           { result = [val[0], val[2]] }

  alt_sequence  : alt_prefix simple_item              { result = [:alt, val[0], val[1]] }

  alt_prefix    : IDENT PIPE                          { result = [val[0]] }
                | alt_prefix IDENT PIPE               { result = val[0] << val[1] }

end

---- header
require 'strscan'

---- inner
  LIST_DIRECTIVES = %w[token left right nonassoc token_class]
  BLOCK_DIRECTIVES = %w[include syntax_error stack_overflow parse_failure parse_accept]
  TYPE_DIRECTIVES = %w[type token_type default_type extra_context extra_argument]

  def parse(str)
    @tokens = tokenize(str)
    @pos = 0
    do_parse
  end

  def next_token
    @tokens[@pos].tap { @pos += 1 }
  end

  def tokenize(str)
    tokens = []
    s = StringScanner.new(str)

    until s.eos?
      case
      when s.scan(/\s+/)
        # skip whitespace
      when s.scan(%r{//[^\n]*})
        tokens << [:COMMENT, s.matched]
      when s.scan(%r{/\*.*?\*/}m)
        tokens << [:COMMENT, s.matched]
      when s.scan(/::=/)
        tokens << [:ASSIGN, '::=']
      when s.scan(/%/)
        tokens << [:PERCENT, '%']
      when s.scan(/\{/)
        content = read_balanced_braces(s)
        tokens << [:BRACED, content]
      when s.scan(/\(/)
        tokens << [:LPAREN, '(']
      when s.scan(/\)/)
        tokens << [:RPAREN, ')']
      when s.scan(/\[/)
        tokens << [:LBRACKET, '[']
      when s.scan(/\]/)
        tokens << [:RBRACKET, ']']
      when s.scan(/\./)
        tokens << [:DOT, '.']
      when s.scan(/\|\|/)
        tokens << [:DPIPE, '||']
      when s.scan(/&&/)
        tokens << [:DAMP, '&&']
      when s.scan(/!/)
        tokens << [:BANG, '!']
      when s.scan(/\|/)
        tokens << [:PIPE, '|']
      when s.scan(/0x[0-9a-fA-F]+|\d+/)
        tokens << [:NUMBER, s.matched]
      when s.scan(/[a-zA-Z_][a-zA-Z0-9_]*/)
        word = s.matched
        case word
        when 'ifdef', 'ifndef', 'if'
          tokens << [:IFDEF, word]
        when 'else'
          tokens << [:ELSE, word]
        when 'endif'
          tokens << [:ENDIF, word]
        when 'fallback'
          tokens << [:FALLBACK, word]
        when 'wildcard'
          tokens << [:WILDCARD, word]
        when 'destructor'
          tokens << [:DESTRUCTOR, word]
        when *LIST_DIRECTIVES
          tokens << [:LIST_DIR, word]
        when *BLOCK_DIRECTIVES
          tokens << [:BLOCK_DIR, word]
        when *TYPE_DIRECTIVES
          tokens << [:TYPE_DIR, word]
        else
          tokens << [:IDENT, word]
        end
      else
        s.getch
      end
    end

    tokens << [false, false]
    tokens
  end

  def read_balanced_braces(s)
    depth = 1
    content = +''
    until s.eos? || depth == 0
      if s.scan(/\{/)
        depth += 1
        content << '{'
      elsif s.scan(/\}/)
        depth -= 1
        content << '}' if depth > 0
      elsif s.scan(/"(?:[^"\\]|\\.)*"/)
        content << s.matched
      elsif s.scan(/'(?:[^'\\]|\\.)*'/)
        content << s.matched
      elsif s.scan(%r{//[^\n]*})
        content << s.matched
      elsif s.scan(%r{/\*.*?\*/}m)
        content << s.matched
      elsif s.scan(/[^{}"'\/]+/)
        content << s.matched
      elsif s.scan(/./)
        content << s.matched
      end
    end
    content
  end
