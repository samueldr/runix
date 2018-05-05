require_relative "../nel.rb"

RSpec.describe NEL do
	let(:parser) { NEL.new }

	context "rules parse" do

		context "spaces" do
			[
				" ",
				"  ",
				" \n ",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.space).to parse(str)
				end
			end
		end

		context "integers" do
			[
				"0",
				"1",
				"9",
				"1234",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.integer).to parse(str)
				end
			end
		end

		context "floating point numbers" do
			[
				"123.45",
				".45",
				".45e1",
				"1.45e1",
				"1.e4",
				"1.E4",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.floating_point).to parse(str)
				end
			end
		end

		context "quoted strings" do
			[
				'""',
				'"a"',
				'"ok"',
				'"ok\""',
				'"${a}"',
				'"${"a"}"',
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.quoted_string).to parse(str)
				end
			end
		end

		context "indented strings" do
			[
				"'' ok ''",
				"'' oki'''doo ''",
				%q[''${"a"}''],
				%q[''${''a''}''],
				%q['' ''${'''a'''} ''],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.indented_string).to parse(str)
				end
			end
		end

		context "URIs" do
			[
				"a:b",
				"http://example.com/",
				"http://google.com/a.b.c",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.uri).to parse(str)
				end
			end
		end

		context "paths" do
			[
				"~/.",
				"/.",
				"/Users/samuel",
				"~/a/b",
				"~/a/b/",
				"<nixpkgs>",
				"<nixpkgs/a>",
				"<nixpkgs/.>",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.path).to parse(str)
				end
			end
			[
				"1",
				"a",
				"./",
				"[]",
				"[a]",
				"[ ]",
				"http",
				"http:",
				"http://",
				"http://a",
				"http:a",
				".////.",
				".////",
				"<nixpkgs/./>",
				"<>",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.path).to_not parse(str)
				end
			end
		end

		context "some values" do
			[
				"true",
				"false",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.boolean).to parse(str)
				end
			end
			it "(null)" do
				expect(parser.null).to parse("null")
			end
		end

		context "identifiers" do
			[
				"a",
				"b",
				"c-d",
				"e_f",
				"test",
				"a2a",
				"test-",
				"test_",
				"_test_",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.identifier).to parse(str)
				end
			end
			[
				"1",
				"-test",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.identifier).to_not parse(str)
				end
			end
		end

		context "lists" do
			[
				"[]",
				"[ ]",
				"[null]",
				"[null null]",
				"[ null null ]",
				'[ "1" 2 true ]',
				"[ [][ ]]",
				"[[[]]]",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.list).to parse(str)
				end
			end
		end

		context "sets" do
			[
				"rec{}",
				"rec {}",
				"{}",
				"{ }",
				"{null=null;}",
				"{null = null;}",
				"{a = b;null = null;}",
				"{ a = b ; null = null ; }",
				"{ a = ''b'' ; }",
				"{inherit;}",
				"{inherit pkgs;}",
				"{inherit pkgs a b;}",
				"{inherit pkgs; a = b;}",
				"{inherit (self);}",
				"{inherit (self) pkgs; a = b;}",
				"{inherit(a)a;}",
				"{inherit (a) a;}",
				%q[{"a" = ''a'';}],
				%q[{"a" = null;}],
				%q[{${null} = null;}],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.set).to parse(str)
				end
			end
			[
				"{inherit pkgs}",
				"{inherita}",
				"{inherit-}",
				"{inherit(a)(a)}",
				"{null}",
				"{null=null}",
				"{null = null}",
				%q[{''a'' = "a";}],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.set).to_not parse(str)
				end
			end
		end

		context "antiquotation" do
			[
				"${1}",
				"${identifier}",
				'${"string"}',
				"${null}",
				"${1+1}",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.antiquotation).to parse(str)
				end
			end
		end

		context "let" do
			[
				"let in",
				"let ina = 1; in",
				"let/**/in",
				%q[let "a" = ''a''; in],
				%q[let "${null}" = ''a''; in],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.let).to parse(str)
					# Also parseable by root parser.
					expect(parser).to parse(str + " 1")
				end
			end
			[
				"let 1 in",
				%q[let "a" = ''a'' in],
				%q[let ${null} = ''a'' in],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser.let).to_not parse(str)
					# Also parseable by root parser.
					expect(parser).to_not parse(str + " 1")
				end
			end
			[
				"let in1",
				"let ina",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser).to_not parse(str)
				end
			end
		end


		context "operator" do
			context "select" do
				[
					"a.b",
					"a . b",
					"a/**/.a",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_select).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "call" do
				[
					"a b",
					"a- b-",
					"a # test\nb",
					"a/* */b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_call).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "arithmetic negation" do
				[
					"-1",
					"-b",
					"-# test\nc",
					"-/* */3",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_arithmetic_negation).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "has attr" do
				[
					"a?b",
					"a ? b",
					"a/* */?/* */b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_has_attr).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "concat lists" do
				[
					"[]++[]",
					"a++b",
					"a ++ b",
					"a/* */++/* */[]",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_concat_lists).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "arithmetic multiplication and division" do
				[
					"a * b",
					"a / b",
					"a/* */*/* */[]",
					"2/*/*/*/*/*/4",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_mul_div).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "arithmetic addition and subtraction" do
				[
					"a + b",
					"a - b",
					"a/* */-/* */[]",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_add_sub).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "boolean negation" do
				[
					"!1",
					"!b",
					"!# test\nc",
					"!/* */3",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_boolean_negation).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "set merge" do
				[
					"{}//{}",
					"a//b",
					"a // b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_set_merge).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "arithmetic comparison" do
				[
					"a>b",
					"a > b",
					"a < b",
					"a>=b",
					"a >= b",
					"a <= b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_arithmetic_comparison).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "equality and inequality" do
				[
					"a==b",
					"a !== b",
					"a == b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_equality_inequality).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "logical and" do
				[
					"a&&b",
					"a && b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_logical_and).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "logical or" do
				[
					"a||b",
					"a || b",
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_logical_or).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			context "logical implication" do
				[
					#"a->b", NOPE!: [a-, >, b]
					"a -> b",
					"a ->b",
					#"(a)->b", # TODO parens
				].each do |str|
					it "(#{str.inspect})" do
						expect(parser.op_logical_implication).to parse(str)
						# Also parseable by root parser.
						expect(parser).to parse(str)
					end
				end
			end
			# TODO : test associativity and binding.
		end
	end

	context "parser parses" do
		context "root with spaces" do
			[
				" 1 ",
				"1 ",
				" 1",
				"  1  ",
				"\t\n1\n\t",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser).to parse(str)
				end
			end
		end

		context "root noise" do
			[
				"",
				" ",
				"#",
				" #",
				" # test",
				" # test\n # test",
				"/**/",
				"/*a*/",
				"/* */",
				"/* a */",
				"/* /* */",
				"/* /* /*/",
				"/* /* /**/",
				"/* */1/* */",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser).to parse(str)
				end
			end
			[
				# Actually valid! (call operator)
				#"1 # test\n1 # test",
				#"/* */1/* */1",
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser).to_not parse(str)
				end
			end
		end

		context "torture" do
			[
				%q[let"a"={a="b";};in{inherit(a)a;}],
			].each do |str|
				it "(#{str.inspect})" do
					expect(parser).to parse(str)
				end
			end
		end
	end
end

