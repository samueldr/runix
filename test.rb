require "pp"
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

	# TODO : nix-like URI parsing (which supposedly is dumb)
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
		#match['a-zA-Z'].repeat(1).as(:protocol) >>
		#str(":") >>
		#match['a-zA-Z/\.'].repeat(1).as(:temp)
	}

	#
	# Whitespace
	#
	rule(:space) {
		(
		match['\t '].as(:horizontal_space) |
		match['\n'].as(:vertical_space)
		)
			.repeat(1).as(:space)
	}
	rule(:space?) {
		space.maybe
	}

	#
	# Path
	#
	rule(:path_definition) {
		# FIXME : all-encompassing path is encompassing anything not parsed!
		# See :string_component
		(
			str("/").repeat().as(:separator) >>
			match['a-zA-Z~\.'].repeat(1).as(:component)
			#(match["/<>"].absent? >> any)
		).as(:path_component).repeat(1) >> str("/").repeat.as(:invalid_trailing_slash)
	}
	rule(:path) {
		(
			(
				str("<") >> (match['/<>'].absent? >> any).repeat(1).as(:nix_path) >> path_definition.maybe >> str(">")
			) |
			path_definition
		).as(:path)
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
	# Operators
	#

	rule(:op_select) {
		value >> space? >> str(".") >> space? >> value
	}

	rule(:op_call) {
		value >> space? >> value
	}

	rule(:operator) {
		# TODO : binding and associativity
		op_select | op_call
	}

	#
	# Compound rules
	#
	rule(:value) {
		list | simple_value
	}
	rule(:simple_value) { null | boolean | number | string | path }

	rule(:expression) { value }

	rule(:_root) { space.repeat >> expression.maybe >> space.repeat }
	root(:_root)
end

# ------------------------------------------------------------------------------

def test(str)
	print "→ "
	pp str
	pp NEL.new.parse(str)
end

puts " - spaces - "

test(" ")
test("  ")
test(" \n ")

test(" 1 ")
test("1 ")
test(" 1")
test("  1  ")
test("\t\n1\n\t")

puts " - integer - "

test("132432")

puts " - floating point - "

test("123.45")
test(".45")
test(".45e1")
test("1.45e1")
test("1.e4")
test("1.E4")

puts " - quoted strings - "

test('"ok"')
test('"ok\""')

puts " - indented strings - "

test("'' ok ''")
test("'' oki'''doo ''")

puts " - URIs - "

test("a:b")
test("http://google.com/")
test("http://google.com/ ")
test(" http://google.com/ ")

puts " - paths - "

test("~/.")
test("/.")
test("/Users/samuel")
test("~/a/b")
test("~/a/b/")
test(".////.")
test(".////")

test("<nixpkgs>")
test("<nixpkgs/a>")

puts "- booleans -"

test("true")
test("false")
test("null")

puts "- lists -"

test("[]")
test("[ ]")
test("[null]")
test("[null null]")
test("[ null null ]")
test('[ "1" 2 true ]')
test("[ [][ ]]")
test("[[[]]]")

puts "- operators -"

test("a.b")
test("a . b")
test("a b")
