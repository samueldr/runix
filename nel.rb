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
	rule(:string_component) { any.as(:string_component) }

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
			str("'''").as(:escaped_single_quote) >> string_component |
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
		identifier | quoted_string
	}
	rule(:set_pair) {
		set_attr_name.as(:lhs) >> space?.as(:lhs_) >> str("=") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	#
	# Identifiers
	#

	rule(:identifier) {
		# ID          [a-zA-Z\_][a-zA-Z0-9\_\'\-]*
		(match['a-zA-Z_'] >> match['a-zA-Z0-9_\'-'].repeat).as(:identifier)
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

	rule(:op_select) {
		# TODO use `attr_path` as expected...
		# TODO : test conformance with `expr_select` from nix.
		value.as(:lhs) >> space?.as(:lhs_) >> str(".") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_call) {
		value.as(:lhs) >> space? >> value.as(:rhs)
	}

	rule(:op_arithmetic_negation) {
		str("-") >> space? >> value
	}
	
	rule(:op_has_attr) {
		value.as(:lhs) >> space?.as(:lhs_) >> str("?") >> space?.as(:rhs_) >> attr_path.as(:rhs)
	}

	rule(:op_concat_lists) {
		value.as(:lhs) >> space?.as(:lhs_) >> str("++") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_mul_div) {
		value.as(:lhs) >> space?.as(:lhs_) >> match['\*/'].as(:operator) >> space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_add_sub) {
		value.as(:lhs) >> space?.as(:lhs_) >> match['\+-'].as(:operator) >> space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_boolean_negation) {
		str("!") >> space? >> value
	}

	rule(:op_set_merge) {
		value.as(:lhs) >> space?.as(:lhs_) >> str("//") >> space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_arithmetic_comparison) {
		value.as(:lhs) >> space?.as(:lhs_) >>
		(
			str("<=") |
			str(">=") |
			str("<") |
			str(">")
		).as(:operator) >>
		space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_equality_inequality) {
		value.as(:lhs) >> space?.as(:lhs_) >>
		(
			str("==") |
			str("!==")
		).as(:operator) >>
		space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_logical_and) {
		value.as(:lhs) >> space?.as(:lhs_) >>
		str("&&") >>
		space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_logical_or) {
		value.as(:lhs) >> space?.as(:lhs_) >>
		str("||") >>
		space?.as(:rhs_) >> value.as(:rhs)
	}

	rule(:op_logical_implication) {
		value.as(:lhs) >> space?.as(:lhs_) >>
		str("->") >>
		space?.as(:rhs_) >> value.as(:rhs)
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
		(null | boolean | list | set | simple_value | identifier).as(:value)
	}
	rule(:simple_value) { number | string | path }

	rule(:expression) { operator | value }


	#
	# Whitespace
	#
	rule(:space) {
		(
		match['\t '].as(:horizontal_space) |
		match['\n'].as(:vertical_space) |
		comment
		)
			.repeat(1).as(:space)
	}

	rule(:space?) {
		space.maybe
	}

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
		space.repeat >> expression.maybe >> space.repeat
	}
	root(:_root)
end
