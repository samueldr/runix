require "parslet"

# Nix Expression Language
# https://nixos.org/nix/manual/#ch-expression-language
# Just enough parsing to re-output the same file, but formatted.
# THIS WILL NEED TO PRESERVE VERTICAL SPACING BETWEEN BLOCKS
class NEL < Parslet::Parser
	#
	# Numbers
	#
	rule(:number) { floating_point | integer }
	rule(:integer) {
		# INT         [0-9]+
		match("[0-9]").repeat(1).as(:integer)
	}
	rule(:floating_point) {
		# FLOAT       (([1-9][0-9]*\.[0-9]*)|(0?\.[0-9]+))([Ee][+-]?[0-9]+)?
		(
			(match("[0-9]").repeat(0)).as(:integer_part) >>
			str(".") >>
			(
				(match("[0-9]").repeat(0) >> match["Ee"] >> match("[0-9]").repeat(1)) |
				(match("[0-9]").repeat(1))
			).as(:floating_part)
		).as(:floating_point)
	}

	#
	# Strings
	#
	rule(:string) { quoted_string | indented_string | uri }

	# Captures a letter from a string...
	# FIXME : find out a better way to handle this.
	# Used until I understand how to capture groups AND handle escaping.
	rule(:string_component) { antiquotation | any }

	rule(:quoted_string) {
		str('"') >> 
		(
			str('\\').as(:escape) >> string_component |
			str('"').absent? >> string_component
		).repeat.as(:quoted_string) >> 
		str('"')
	}

	rule(:indented_string) {
		str("''") >> 
		(
			(str("''") >> match["'$"]).as(:escape) |
			str("''").absent? >> string_component
		).repeat.as(:indented_string) >> 
		str("''")
	}

	rule(:uri) {
		# URI         [a-zA-Z][a-zA-Z0-9\+\-\.]*\:[a-zA-Z0-9\%\/\?\:\@\&\=\+\$\,\-\_\.\!\~\*\']+
		(
			(
				match("[a-zA-Z]") >>
				match("[a-zA-Z0-9\+\-\.]").repeat
			).as(:protocol) >>
			str(":") >>
			match("[a-zA-Z0-9\%\/\?\:\@\&\=\+\$\,\-\_\.\!\~\*\']").repeat(1).as(:leftover)
		).as(:uri)
	}

	#
	# Path
	#

	# Nix's grammar defines three types of paths:
	# PATH        [a-zA-Z0-9\.\_\-\+]*(\/[a-zA-Z0-9\.\_\-\+]+)+\/?
	# HPATH       \~(\/[a-zA-Z0-9\.\_\-\+]+)+\/?
	# SPATH       \<[a-zA-Z0-9\.\_\-\+]+(\/[a-zA-Z0-9\.\_\-\+]+)*\>
	rule(:path_letter) { match['[a-zA-Z0-9\.\_\-\+]'] }
	rule(:path_separator) { str("/").as(:path_separator) }
	rule(:path__repeated) { ( path_separator >> path_letter.repeat(1).as(:path_component) ).repeat(1) }
	rule(:path) { (npath | hpath | spath).as(:path) }
	rule(:npath) {
		path_letter.repeat >> path__repeated >> path_separator.maybe
	}

	rule(:hpath) {
		str("~").as(:path_component) >> path__repeated >> path_separator.maybe.as(:invalid_trailing_slash)
	}

	rule(:spath) {
		str("<") >> path_letter.repeat(1).as(:env_path) >> path__repeated.maybe >> str(">")
	}

	#
	# Values
	#
	rule(:boolean) { str("true").as(:true) | str("false").as(:false) }
	rule(:null) { str("null").as(:null) }

	#
	# Lists
	#
	rule(:list) {
		(
			str("[") >> (
				value.as(:value) | space.as(:space)
			).repeat >> str("]")
		).as(:list)
	}

	#
	# Sets
	#
	rule(:set) {
		(str("rec") >> space?).maybe.as(:rec) >>
		str("{") >> space? >>
		(
			(set_inherit | set_pair) >> space?.as(:before_) >> str(";") >> space?.as(:after_)
		).repeat.as(:values) >>
		str("}")
	}
	rule(:set_inherit) {
		# Parenthesis makes this hard!
		str("inherit") >>
		(space?.as(:lhs_) >> str("(") >> identifier >> str(")") >> space?.as(:rhs?)).maybe.as(:set)>>
		(space? >> identifier ).repeat(0).as(:attributes)
	}
	rule(:set_attr_name) {
		# TODO : Add antiquotation (${})
		identifier | quoted_string | antiquotation
	}
	rule(:set_pair) {
		set_attr_name.as(:lhs) >> space?.as(:lhs_) >> str("=") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	#
	# Antiquotation
	#
	rule(:antiquotation) {
		str("${") >> expression >> str("}")
	}

	#
	# Let
	#
	rule(:let) {
		str("let") >> space?.as(:before_) >>
		(
			let_pair >> space?.as(:before_) >> str(";") >> space?.as(:after_)
		).repeat.as(:values) >>
		space?.as(:after_) >> str("in") >> (identifier_match | number).absent?
	}
	rule(:let_attr_name) {
		# TODO : Add antiquotation (${})
		identifier | quoted_string
	}
	rule(:let_pair) {
		let_attr_name.as(:lhs) >> space?.as(:lhs_) >> str("=") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	#
	# Function
	#
	rule(:function_set_pattern_identifier) {
		space?.as(:before_) >>
		(identifier.as(:identifier)) >>
		space?.as(:middle_) >>
		(str("?") >> space? >> expression).maybe >>
		space?.as(:after_)
	}
	rule(:function_set_pattern_with_args) {
		(function_set_pattern >> (space?.as(:before_) >> str("@") >> space?.as(:after_) >> identifier).maybe) |
		((identifier >> str("@")).maybe >> function_set_pattern)
	}
	rule(:function_set_pattern) {
		str("{") >> space? >>
		(
			function_set_pattern_identifier >>
			(str(",") >> function_set_pattern_identifier).repeat
		).repeat.as(:values) >>
		(str(",") >> space?.as(:before_) >> str("...").as(:additional) >> space?.as(:after_)).maybe >>
		str("}")
	}
	rule(:function_pattern) {
		function_set_pattern_with_args.as(:set) |
		(identifier.as(:identifier) >> (space? >> str("@")).absent?)
	}
	rule(:function) {
		function_pattern.as(:pattern) >> str(":") >> space >> expression.as(:body)
	}

	#
	# Conditional
	#
	rule(:conditional) {
		spaced(
			str("if"),
			expression.as(:if),
			str("then"),
			expression.as(:then),
			str("else"),
			expression.as(:else),
		)
	}

	#
	# Assertions
	#
	rule(:assert) {
		spaced(
			str("assert"),
			expression.as(:assertion),
			str(";"),
			expression.as(:value),
		)
	}

	#
	# With expressions
	#
	rule(:with) {
		spaced(
			str("with"),
			expression.as(:set),
			str(";"),
			expression.as(:expr),
		)
	}

	#
	# Identifiers
	#

	# Marks a word as forbidden for identifiers.
	def not_keyword(string)
		(str(string) >> identifier_match.absent?).absent?
	end

	rule(:identifier_match) {
		match['a-zA-Z_'] >> match['a-zA-Z0-9_\'-'].repeat
	}
	rule(:identifier) {
		# ID          [a-zA-Z\_][a-zA-Z0-9\_\'\-]*
		not_keyword("if") >>
		not_keyword("then") >>
		not_keyword("else") >>
		not_keyword("assert") >>
		not_keyword("with") >>
		not_keyword("let") >>
		not_keyword("in") >>
		not_keyword("rec") >>
		not_keyword("inherit") >>
		not_keyword("or") >>
		(identifier_match).as(:identifier)
	}

	rule(:attr_path) {
		# 337   | expr_op '?' attrpath { $$ = new ExprOpHasAttr($1, *$3); }
		#                     ^^^^^^^^
		# TODO: rhs: expecting ID or OR_KW or DOLLAR_CURLY or '"', at (string):1:5
		#       this is attrpath in the source... see also where-else it's used and I should use it.
		identifier
	}

	#
	# Operators
	#

	# Makes an operator.
	# Use a symbol for the parser rule.
	def self._op(name, operators, lhs: :value, rhs: :value, op_type: :str)
		operators = [operators] unless operators.is_a? Array
		rule("op_#{name}".to_sym) {
			spaced(
				send(lhs).as(:lhs),
				operators.map do |operator|
					send(op_type, operator)
				end.reduce(&:|).as(:operator),
				send(rhs).as(:rhs),
			)
		}
	end

	# Most operators are simple; expressions (or subtypes) with an operator
	# and optional spaces around.


	# TODO use `attr_path` as expected...
	# TODO : test conformance with `expr_select` from nix.
	_op(:select, ".", rhs: :attr_path)
	_op(:has_attr, "?", rhs: :attr_path)

	_op(:concat_lists, "++")
	_op(:mul_div, '[\*/]', op_type: :match)
	_op(:add_sub, '[\+-]', op_type: :match)
	_op(:set_merge, "//")
	_op(:arithmetic_comparison, ["<=", ">=", "<", ">"])
	_op(:equality_inequality, ["==", "!=="])
	_op(:logical_and, "&&")
	_op(:logical_or, "||")
	_op(:logical_implication, "->")

	# The call operator is harder...
	# It is `expression expression`, but the space *may* not be present
	# if and only if it cannot be confused for an identifer.
	# → x[] a{} {}x []x
	rule(:op_call) {
		# FIXME : expression will either need to be parenthsized OR spaced... it cannot be abcd it needs one of: (ab)cd ab(cd) ab cd
		spaced(value.as(:lhs), value.as(:rhs))
	}

	rule(:op_arithmetic_negation) {
		spaced(str("-"), expression)
	}

	rule(:op_boolean_negation) {
		spaced(str("!"), expression)
	}

	rule(:operator) {
		# https://nixos.org/nix/manual/#idm140737318018576
		# TODO : binding and associativity
		op_select |
		op_call |
		op_arithmetic_negation |
		op_has_attr |
		op_concat_lists |
		op_mul_div |
		op_add_sub |
		op_boolean_negation |
		op_set_merge |
		op_arithmetic_comparison |
		op_equality_inequality |
		op_logical_and |
		op_logical_or |
		op_logical_implication
	}

	#
	# Compound rules
	#
	rule(:value) {
		(null | boolean | function | list | set | simple_value | identifier).as(:value)
	}
	rule(:simple_value) { number | string | path }
	
	def parenthesized(bit)
		spaced(str("("), bit, str(")"))
	end

	rule(:expression_fragment) {
		(
		(let >> space?).maybe >> (conditional | assert | with | operator | value)
		).as(:expression_fragment)
	}

	rule(:expression) {
		parenthesized(expression_fragment) | expression_fragment
	}

	#
	# Whitespace
	#
	rule(:space) {
		# We need to keep track of vertical spaces and horizontal spaces.
		# Comments are treated as whitespace ( 1/**/+/**/1 )
		(
		match['\t '].as(:horizontal_space) |
		match['\n'].as(:vertical_space) |
		comment
		).repeat(1).as(:space)
	}
	rule(:space?) { space.maybe }

	#
	# Interleaves spaces in the parsing.
	#
	#     a+b → a_+_b
	#
	# Every space is identified by its position as `_i`.
	#
	def spaced(*bits)
		bits.zip(
			(bits.length).times.map {|i| space?.as("_#{i}".to_sym) }
		)
		.flatten()[0..-2]
		.reduce(&:>>)
	end

	rule(:h_comment) {
		str("#") >> (match['\n'].absent? >> any).repeat.as(:text) >> str("\n").maybe
	}

	rule(:c_comment) {
		str("/*") >> (str("*/").absent? >> any).repeat.as(:text) >> str("*/").maybe
	}

	rule(:comment) {
		h_comment.as(:h_comment) | c_comment.as(:c_comment)
	}

	# Allows root string to be composed of an expression surrounded with spaces.
	# (This could be handled through stripping whitespace before parsing, but eh)
	rule(:_root) {
		space.repeat.as(:_1) >> expression.maybe.as(:expression) >> space.repeat.as(:_2)
	}
	root(:_root)
end
