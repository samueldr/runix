require "pp"
require_relative "./nel.rb"

data = STDIN.read
puts data
puts
puts

begin
	pp NEL.new.parse(data)
rescue Parslet::ParseFailed => error
	puts error.parse_failure_cause.ascii_tree
end
