# This parser can parse a simple subset of Cheetah's syntax.

from spitfire.compiler.ast import *

%%

parser SpitfireParser:
  token DOT: '\.'
  token NUM:   '[0-9]+'
  token ID:    '[A-Za-z_][0-9A-Za-z_]*'

  #token STR:   r'"([^\\"]+|\\.)*"'
  token SINGLE_QUOTE_STR: r"(?:[^'\\]|\\.)*"
  token DOUBLE_QUOTE_STR: r'(?:[^"\\]|\\.)*'

  token SINGLE_LINE_COMMENT: '#.*?\n'
  token MULTI_LINE_COMMENT: '\*[\W\w\S\s]+\*#'
  token ASSIGN_OPERATOR: '='
  # 'in' requires whitespace around it, but that is the only
  # such operator
  token COMP_OPERATOR: '[ \t]*(<=|>=|==|>|<|!=|[ \t]+in[ \t]+)[ \t]*'
  token OPEN_PAREN: '[ \t]*\([ \t]*'
  # don't gobble whitespace in the placeholder context
  # this leads to some strange behavior and mis-parsing of lines like this:
  # $value (something to echo)
  # the only dynamic value there is $value
  token PLACEHOLDER_OPEN_PAREN: '\([ \t]*'
  #token CLOSE_PAREN: '[ \t]*\)[ \t]*'
  # changing this to not gobble trailing whitespace - important for placeholder
  # functions in text
  token CLOSE_PAREN: '[ \t]*\)'
  token OPEN_BRACKET: '[ \t]*\[[ \t]*'
  token CLOSE_BRACKET: '[ \t]*\][ \t]*'
  token PLACEHOLDER_OPEN_BRACE: '\{[ \t]*'
  token PLACEHOLDER_CLOSE_BRACE: '[ \t]*\}'
  token OPEN_BRACE: '[ \t]*\{[ \t]*'
  token CLOSE_BRACE: '[ \t]*\}[ \t]*'
  token PIPE: '[ \t]*\|[ \t]*'

  token COMMA_DELIMITER: '[ \t]*,[ \t]*'
  token COLON_DELIMITER: '[ \t]*:[ \t]*'

  token SPACE: '[ \t]+'
  token CLOSE_DIRECTIVE_TOKEN: '[ \t]*[\n#]'
  token END_DIRECTIVE: '#end'
  token START_DIRECTIVE: '#'
  token START_PLACEHOLDER: '\$'
  token NEWLINE: '\n'
  token PYTHON_LINE: '.+'
  token TEXT: '[^#\$\n]+'
  token END:   '$'

  # don't allow directive inside i18n
  # fixme: need to allow an escape hatch in case you want a literal # in the
  # i18n message body
  token I18N_BODY: '[^#]+'

  # need to make close_directive a rule because sometimes optional trailing
  # whitespace may get slurped up as SPACE depending on how far things got
  # scanned ahead
  rule CLOSE_DIRECTIVE:
    [ SPACE ] CLOSE_DIRECTIVE_TOKEN {{ return CLOSE_DIRECTIVE_TOKEN }}

  rule goal:
    {{ template = TemplateNode() }}
    ( block<<start=True>> {{ template.append(block) }} ) *
    END {{ return template }}    

  rule fragment_goal:
    {{ fragment = FragmentNode() }}
    ( block<<start=True>> {{ fragment.append(block) }} ) *
    END {{ return fragment}}

  rule i18n_goal:
    {{ fragment = FragmentNode() }}
    # note: need to put the position start here based on the internals of how
    # yapps generates the parsing loops
    {{ start_pos = 0 }}
    (
      #{{ print "scan:", self._scanner.pos, "parse:", self._pos }}
      text_or_placeholders<<start=True>>
      #{{ print "type:", text_or_placeholders.__class__.__name__, "start:", start_pos, "end:", self._scanner.pos, "data: '%s'" % getattr(text_or_placeholders, 'value', ''), "len:", len(getattr(text_or_placeholders, 'value', '') or '') }}
      #{{ try: print "  token:", self._scanner.tokens[self._pos - 1]}}
      #{{ except: print "  no token" }}
      #{{ end_pos = self._scanner.pos }}
      # try to get the last used index of the input stream
      {{ end_pos = self._scanner.tokens[self._pos-1][1] }}
      {{ fragment.append(text_or_placeholders) }}
      {{ text_or_placeholders.start = start_pos }}
      {{ text_or_placeholders.end = end_pos }}
      {{ start_pos = end_pos }}
    ) *
    END {{ return fragment}}

  rule statement:
        'implements' SPACE ID CLOSE_DIRECTIVE {{ return ImplementsNode(ID) }}
        |
        'extends' SPACE modulename CLOSE_DIRECTIVE {{ return ExtendsNode(modulename) }}
        |
        'absolute_extends' SPACE modulename CLOSE_DIRECTIVE {{ return AbsoluteExtendsNode(modulename) }}
        |
        'from' SPACE modulename SPACE 'import' SPACE identifier CLOSE_DIRECTIVE {{ return FromNode(modulename, identifier) }}
        |
        'import' SPACE modulename CLOSE_DIRECTIVE {{ return ImportNode(modulename) }}
        |
        'slurp' CLOSE_DIRECTIVE {{ return CommentNode('slurp') }}
        |
        'break' CLOSE_DIRECTIVE {{ return BreakNode() }}
        |
        'continue' CLOSE_DIRECTIVE {{ return ContinueNode() }}
        |
        'attr' SPACE placeholder SPACE ASSIGN_OPERATOR SPACE literal CLOSE_DIRECTIVE
        {{ return AttributeNode(placeholder.name, literal) }}
        |
        'filter' SPACE identifier CLOSE_DIRECTIVE
        {{ return AttributeNode('_filter_function', identifier) }}
        |
        'set' SPACE placeholder {{ _lhs = IdentifierNode(placeholder.name) }}
        [ SPACE ] ASSIGN_OPERATOR [ SPACE ] expression {{ _rhs = expression }}
        CLOSE_DIRECTIVE {{ return AssignNode(_lhs, _rhs) }}
        |
        'echo' SPACE literal {{ _true_exp = literal }}
         {{ _test_exp, _false_exp = None, None }}
         [ SPACE 'if' SPACE expression {{ _test_exp = expression }}
           [ SPACE 'else' SPACE literal {{ _false_exp = literal }}
           ]
         ]
         CLOSE_DIRECTIVE {{ return EchoNode(_true_exp, _test_exp, _false_exp) }}
        
  rule modulename:
    identifier {{ _module_name_list = [identifier] }}
    ( DOT identifier {{ _module_name_list.append(identifier) }} ) *
    {{ return _module_name_list }}

  rule directive:
    START_DIRECTIVE
    {{ _node_list = NodeList() }}
      (
        SINGLE_LINE_COMMENT {{ _node_list.append(CommentNode(START_DIRECTIVE + SINGLE_LINE_COMMENT)) }}
        |
        MULTI_LINE_COMMENT {{ _node_list.append(CommentNode(START_DIRECTIVE +MULTI_LINE_COMMENT)) }}
        |
        'block' SPACE ID CLOSE_DIRECTIVE {{ _block = BlockNode(ID) }}
        {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
        ( block<<start>> {{ _block.append(block) }} ) *
        {{ make_optional(_block.child_nodes) }}
        END_DIRECTIVE SPACE 'block' CLOSE_DIRECTIVE {{ _node_list.append(_block) }}
        |
        'i18n' {{ _macro = MacroNode('i18n') }}
        [ OPEN_PAREN
          [ macro_parameter_list {{ _macro.parameter_list = macro_parameter_list }} ]
          CLOSE_PAREN
        ]
        CLOSE_DIRECTIVE
        {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
        {{ _macro.value = '' }}
        (
          I18N_BODY {{ _macro.value += I18N_BODY }}
          [ START_DIRECTIVE {{ _macro.value += START_DIRECTIVE }}
          ]
        )*
        END_DIRECTIVE SPACE 'i18n' CLOSE_DIRECTIVE {{ _node_list.append(_macro) }}
        |
        'def' SPACE ID {{ _def = DefNode(ID) }}
        [ OPEN_PAREN
          [ parameter_list {{ _def.parameter_list = parameter_list }} ]
          CLOSE_PAREN ]
        CLOSE_DIRECTIVE
        {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
        ( block<<start>> {{ _def.append(block) }} ) *
        {{ make_optional(_def.child_nodes) }}
        END_DIRECTIVE SPACE 'def' CLOSE_DIRECTIVE {{ _node_list.append(_def) }}
        |
        'for[ \t]*' target_list '[ \t]*in[ \t]*' expression_list CLOSE_DIRECTIVE
        {{ _for_loop = ForNode(target_list, expression_list) }}
        {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
        ( block<<start>> {{ _for_loop.append(block) }} ) *
        {{ make_optional(_for_loop.child_nodes) }}
        END_DIRECTIVE SPACE 'for' CLOSE_DIRECTIVE {{ _node_list.append(_for_loop) }}
        |
        'if' SPACE expression CLOSE_DIRECTIVE {{ _if_node = IfNode(expression) }}
        {{ _last_condition_node = _if_node }}
        {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
        ( block<<start>> {{ _if_node.append(block) }} ) *
        {{ make_optional(_if_node.child_nodes) }}
        (
          '#elif' SPACE expression CLOSE_DIRECTIVE {{ _elif_node = IfNode(expression) }}
          {{ _last_condition_node.else_.append(_elif_node) }}
          {{ _last_condition_node = _elif_node }}
          {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
          ( block<<start>> {{ _elif_node.append(block) }} ) *
        ) *
        {{ make_optional(_last_condition_node.child_nodes) }}
        [ '#else' CLOSE_DIRECTIVE
          {{ start = CLOSE_DIRECTIVE.endswith('\n') }}
          ( block<<start>> {{ _last_condition_node.else_.append(block) }} ) *
          {{ make_optional(_last_condition_node.else_.child_nodes) }}
        ]
        END_DIRECTIVE SPACE 'if' CLOSE_DIRECTIVE {{ _node_list.append(_if_node) }}
        |
        statement {{ statement.statement = True }}
        {{ _node_list.append(statement) }}
        |
        {{ _node_list.append(TextNode(START_DIRECTIVE)) }}
      )
    {{ return _node_list }}


  # NOTE: if we are at the start of a line, we mark the initial whitespace as
  # optional. this is sort of a hack - but i can't quite figure out the right
  # way to describe this syntax
  rule block<<start=False>>:
    directive {{ return directive }}
    |
    text {{ return text }}
    |
    SPACE {{ _node_list = NodeList() }}
    {{ _node_list.append(WhitespaceNode(SPACE)) }}
    [ directive {{ if start: _node_list[-1] = OptionalWhitespaceNode(SPACE) }}
      {{ _node_list.append(directive) }} ]
    {{ return _node_list }}
    |
    NEWLINE {{ _node_list = NodeList() }}
    {{ _node_list.append(NewlineNode(NEWLINE)) }}
    [
      SPACE {{ _node_list.append(WhitespaceNode(SPACE)) }}
      [
        directive {{ _node_list[-1] = OptionalWhitespaceNode(SPACE) }}
        {{ _node_list.append(directive) }}
        ]
    ]
    {{ return _node_list }}
    |
    {{ _parameter_list = None }}
    START_PLACEHOLDER {{ _primary = TextNode(START_PLACEHOLDER) }}
    [
      (
      PLACEHOLDER_OPEN_BRACE placeholder_in_text
      {{ _primary = placeholder_in_text }}
      [
        PIPE placeholder_parameter_list
        {{ _parameter_list = placeholder_parameter_list }}
      ]
      PLACEHOLDER_CLOSE_BRACE
      |
      placeholder_in_text {{ _primary = placeholder_in_text }}
      )
    ]
    {{ if type(_primary) != TextNode: return PlaceholderSubstitutionNode(_primary, _parameter_list) }}
    {{ return _primary }}
    
  rule text_or_placeholders<<start=False>>:
    ## in this context, a # is just a #
    START_DIRECTIVE {{ return TextNode(START_DIRECTIVE) }}
    |
    text {{ return text }}
    |
    SPACE {{ _node_list = NodeList() }}
    {{ _node_list.append(WhitespaceNode(SPACE)) }}
    {{ return _node_list }}
    |
    NEWLINE {{ _node_list = NodeList() }}
    {{ _node_list.append(NewlineNode(NEWLINE)) }}
    [
      SPACE {{ _node_list.append(WhitespaceNode(SPACE)) }}
    ]
    {{ return _node_list }}
    |
    {{ _parameter_list = None }}
    START_PLACEHOLDER {{ _primary = TextNode(START_PLACEHOLDER) }}
    [
      (
      PLACEHOLDER_OPEN_BRACE placeholder_in_text
      {{ _primary = placeholder_in_text }}
      [
        PIPE placeholder_parameter_list
        {{ _parameter_list = placeholder_parameter_list }}
      ]
      PLACEHOLDER_CLOSE_BRACE
      |
      placeholder_in_text {{ _primary = placeholder_in_text }}
      )
    ]
    {{ if type(_primary) == TextNode: return _primary }}
    {{ _placeholder_sub = PlaceholderSubstitutionNode(_primary, _parameter_list) }}
    {{ return _placeholder_sub }}

  rule text:
    TEXT {{ return TextNode(TEXT) }}

  rule placeholder_in_text:
    ID {{ _primary = PlaceholderNode(ID) }}
    (
      placeholder_suffix_expression<<_primary>>
      {{ _primary = placeholder_suffix_expression }}
    ) *
    {{ return _primary }}

  rule placeholder_suffix_expression<<_previous_primary>>:
    (
      DOT ID {{ _primary = GetUDNNode(_previous_primary, ID) }}
      |
      PLACEHOLDER_OPEN_PAREN {{ _arg_list = None }}
      [ argument_list {{ _arg_list = argument_list }} ]
      # need this expression here to make a bare placeholder in text not
      # gobble trailing white space
      CLOSE_PAREN {{ _primary = CallFunctionNode(_previous_primary, _arg_list) }}
      |
      OPEN_BRACKET
      (
        expression 
        {{ _primary = SliceNode(_previous_primary, expression) }}
      )
      CLOSE_BRACKET
    )
    {{ return _primary }}

  rule placeholder:
    START_PLACEHOLDER
    {{ _token_ = self._peek('ID') }}
    {{ if _token_ == 'ID': return PlaceholderNode(self._scan('ID')) }}
    # I had to manually hack this up - there is a problem in the parser
    # generator (or my understanding of it) where the optional clause
    # causes the parser to 'peek' at a bunch of extra tokens in what appears
    # to be a context-insensitive way. this causes a problem with with the
    # "ambiguous-in" test case.
    # [ ID {{ return PlaceholderNode(ID) }} ]
    {{ return TextNode(START_PLACEHOLDER) }}

  rule target_list:
    {{ _target_list = TargetListNode() }}
    target {{ _target_list.append(target) }}
    (COMMA_DELIMITER target {{ _target_list.append(target) }} )*
    # this optional comma cause a SPACE scan in the parse function
    #[","]
    {{ return _target_list }}

  rule expression_list:
    {{ _expression_list = ExpressionListNode() }}
    expression {{ _expression_list.append(expression) }}
    (COMMA_DELIMITER expression {{ _expression_list.append(expression) }} )*
    # this optional comma cause a SPACE scan in the parse function
    #[","]
    {{ return _expression_list }}


  rule target:
    placeholder {{ return TargetNode(placeholder.name) }}
    |
    OPEN_PAREN target_list CLOSE_PAREN {{ return target_list }}
    |
    OPEN_BRACKET target_list CLOSE_BRACKET {{ return target_list }}

   rule parameter:
     placeholder {{ _node = ParameterNode(placeholder.name) }}
     [ ASSIGN_OPERATOR expression {{ _node.default = expression }} ]
     {{ return _node }}

   rule parameter_list:
     {{ _parameter_list = ParameterListNode() }}
     parameter {{ _parameter_list.append(parameter) }}
     (COMMA_DELIMITER parameter {{ _parameter_list.append(parameter) }} ) *
     {{ return _parameter_list }}
     
   ## restricted data types for macros
   rule macro_parameter:
     placeholder {{ _node = ParameterNode(placeholder.name) }}
     [ ASSIGN_OPERATOR literal {{ _node.default = literal }} ]
     {{ return _node }}

   rule macro_parameter_list:
     {{ _parameter_list = ParameterListNode() }}
     macro_parameter {{ _parameter_list.append(macro_parameter) }}
     (COMMA_DELIMITER macro_parameter {{ _parameter_list.append(macro_parameter) }} ) *
     {{ return _parameter_list }}
   

   rule literal_or_identifier:
     literal {{ return literal }}
     |
     identifier {{ return identifier }}

   ## restricted data types for placeholder args
   rule placeholder_parameter:
     identifier {{ _node = ParameterNode(identifier.name) }}
     [ ASSIGN_OPERATOR literal_or_identifier {{ _node.default = literal_or_identifier }} ]
     {{ return _node }}

   rule placeholder_parameter_list:
     {{ _parameter_list = ParameterListNode() }}
     placeholder_parameter {{ _parameter_list.append(placeholder_parameter) }}
     (COMMA_DELIMITER placeholder_parameter {{ _parameter_list.append(placeholder_parameter) }} ) *
     {{ return _parameter_list }}

  rule stringliteral:
    '"' DOUBLE_QUOTE_STR '"'
    {{ return unicode(eval('"%s"' % DOUBLE_QUOTE_STR)) }}
    |
    "'" SINGLE_QUOTE_STR "'"
    {{ return unicode(eval("'%s'" % SINGLE_QUOTE_STR)) }}

  # had to factor out the floats
  rule literal:
    "True" {{ return LiteralNode(True) }}
    |
    "False" {{ return LiteralNode(False) }}
    |
    stringliteral {{ return LiteralNode(stringliteral) }}
    |
    NUM {{ int_part = NUM }}
    [ "\." NUM {{ return LiteralNode(float('%s.%s' % (int_part, NUM))) }} ]
    {{ return LiteralNode(int(int_part)) }}
   
  rule identifier:
    ID {{ return IdentifierNode(ID) }}

  rule primary<<in_placeholder_context=False>>:
    (
      placeholder {{ _primary = placeholder }}
      |
      # atom
      identifier {{ _primary = identifier }}
      {{ if in_placeholder_context: _primary = PlaceholderNode(_primary.name) }}
      |
      literal {{ _primary = literal }}
      |
      OPEN_BRACKET {{ _list_literal = ListLiteralNode() }}
      [
        expression {{ _list_literal.append(expression) }}
        ( COMMA_DELIMITER expression {{ _list_literal.append(expression) }} ) *
      ]
      CLOSE_BRACKET {{ _primary = _list_literal }}
      |
      OPEN_PAREN {{ _tuple_literal = TupleLiteralNode() }}
      [
        expression {{ _tuple_literal.append(expression) }}
        ( COMMA_DELIMITER expression {{ _tuple_literal.append(expression) }} ) *
      ]
      CLOSE_PAREN {{ _primary = _tuple_literal }}
      |
      OPEN_BRACE {{ _dict_literal = DictLiteralNode() }}
      [
        expression {{ _key = expression }}
        COLON_DELIMITER
        expression {{ _dict_literal.append((_key, expression)) }}
        ( COMMA_DELIMITER expression {{ _key = expression }}
          COLON_DELIMITER expression
          {{ _dict_literal.append((_key, expression)) }}
        ) *
      ]
      # need PLACEHOLDERNODE to handle optional whitespace parsing
      (CLOSE_BRACE | PLACEHOLDER_CLOSE_BRACE) {{ _primary = _dict_literal }}
    )
    (
      placeholder_suffix_expression<<_primary>>
      {{ _primary = placeholder_suffix_expression }}
    ) *
    {{ return _primary }}

  # extra rules for parsing the attribute language
  rule define_list:
    argument_list END {{ return argument_list }}

  rule rhs_expression:
    expression END {{ return expression }}

  # TODO: need to factor out commonalities of pargs and kargs patterns
  # FIXME: seems like a hack - should these all be ParameterNodes and replace
  # the name arg with a real expression?
  rule argument_list:
    {{ _pargs, _kargs = [], [] }}
    expression {{ _arg = expression }}
    (
    COMMA_DELIMITER {{ _pargs.append(_arg) }}
    expression {{ _arg = expression }}
    ) *
    [
    ASSIGN_OPERATOR
    {{ if not isinstance(_arg, (IdentifierNode)): raise SyntaxError(self._scanner.pos, "keyword arg can't be complex expression: %s" % _arg) }}
    {{ _karg = ParameterNode(_arg.name) }}
    {{ _arg = None }}
    expression {{ _karg.default = expression }}
    {{ _kargs.append(_karg) }}
    (
      COMMA_DELIMITER
      identifier {{ _karg = ParameterNode(identifier.name) }}
      ASSIGN_OPERATOR
      expression {{ _karg.default = expression }}
      {{ _kargs.append(_karg) }}
    ) *
    ]
    {{ if _arg: _pargs.append(_arg) }}
    {{ return ArgListNode(_pargs, _kargs) }}

  rule expression:
    or_test {{ return or_test }}

  rule or_test:
    and_test {{ _test = and_test }}
    ( '[ \t]*or[ \t]*' and_test {{ _test = BinOpExpressionNode('or', _test, and_test) }} ) *
    {{ return _test }}

  rule and_test:
    not_test {{ _test = not_test }}
    ( '[ \t]*and[ \t]*' not_test {{ _test = BinOpExpressionNode('and', _test, not_test) }} ) *
    {{ return _test }}
    
  rule not_test:
    comparison {{ return comparison }}
    |
    "[ \t]*not[ \t]*" not_test {{ return UnaryOpNode('not', not_test) }}
    
  rule u_expr:
    primary {{ return primary }}
    |
    '[ \t]*\-[ \t]*' u_expr {{ return UnaryOpNode('-', u_expr) }}

  rule m_expr:
    u_expr {{ _expr = u_expr }}
    ( '[ \t]*\*[ \t]*' u_expr {{ _expr = BinOpExpressionNode('*', _expr, u_expr) }} ) *
    ( '[ \t]*\/[ \t]*' u_expr {{ _expr = BinOpExpressionNode('/', _expr, u_expr) }} ) *
    ( '[ \t]*\%[ \t]*' u_expr {{ _expr = BinOpExpressionNode('%', _expr, u_expr) }} ) *
    {{ return _expr }}

  rule a_expr:
    m_expr {{ _expr = m_expr }}
    ( '[ \t]*\+[ \t]*' m_expr {{ _expr = BinOpExpressionNode('+', _expr, m_expr) }} ) *
    ( '[ \t]*\-[ \t]*' m_expr {{ _expr = BinOpExpressionNode('-', _expr, m_expr) }} ) *
    {{ return _expr }}

  rule comparison:
    a_expr {{ _left_side = a_expr }}
    ( COMP_OPERATOR a_expr {{ _left_side = BinOpExpressionNode(COMP_OPERATOR.strip(), _left_side, a_expr) }} ) *
    {{ return _left_side }}
