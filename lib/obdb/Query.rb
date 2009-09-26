#require "my/mytrace"

=begin
class Widget
	class << self
		def color
			Query.new(QueryField.new(Widget,:color))
		end

		def size
			Query.new(QueryField.new(Widget,:size))
		end
	end
end
=end

class QueryField
	def initialize(klass, member)
		@klass, @member = klass, member
	end

	def to_s
		@klass.to_s + ":" + @member.to_s
	end
end

class Query
	class << self
		def new_from_query_string(query_string)
			x = Query.new("x")
			eval (query_string)
		end
	end

	QUERY_OBJECT = :query_object	# this is a place holder for the object that we are looking for
	DEF_UNARY_OPERATORS = ["kind_of?", "!"]
	DEF_BINARY_OPERATORS = ["<", ">", "&", "|", "==", ">=", "<=", "=~"]
	OPERATORS = DEF_BINARY_OPERATORS + ["."]
	
	# define operator functions
	DEF_BINARY_OPERATORS.each do |op|
		module_eval %Q{
			def #{op}(other)
				if !other.kind_of?(Query) then
					other = Query.new(other)
				end
				Query.new("#{op}", self, other)
			end
		}
	end

	attr_reader :left, :right, :value
	def initialize(*args)
		@left = @right = @value = nil
		if args.size == 0 then
			@value = QUERY_OBJECT
		elsif args.size == 1 then
			@value = args.shift
		elsif args.size == 2 then
			op = args.shift
			if UNARY_OPERATORS.include?(op) then
				@value = args.shift
			else
				raise "Invalid unary operator #{op}"
			end
		elsif args.size == 3 then
			op = args.shift
			#print "looking for '#{op}' in #{OPERATORS.inspect}\n"
			if OPERATORS.include?(op) then
				@value = op
				left, right = args
				
				if left.kind_of?(Query)
					@left = left
				else
					@left = Query.new(left)
				end

				if right.kind_of?(Query)
					@right = right
				else
					@right = Query.new(right)
				end
			else
				raise "invalid binary operator #{op}"
			end
		end
	end
=begin
	def >(other)
		if !other.kind_of?(Query) then
			other = Query.new(other)
		end
		Query.new(">", self, other)
	end

	def <(other)
		if !other.kind_of?(Query) then
			other = Query.new(other)
		end
		Query.new("<", self, other)
	end

	def &(other)
		if !other.kind_of?(Query) then
			other = Query.new(other)
		end
		Query.new("&", self, other)
	end

	def |(other)
		if !other.kind_of?(Query) then
			other = Query.new(other)
		end
		Query.new("&", self, other)
	end
=end

	def matches(obj)
		evaluate(obj) == true
	end

	def evaluate(obj=nil)
		$TRACE.debug 6, "in evaluate (#{@left.inspect}, #{@right.inspect}, #{@value.inspect})"
		if @left.nil? && @right.nil? then
			return @value
		elsif right.nil? then
			$TRACE.debug 6, "in evaluate value = #{@value.inspect}"
			ret = eval(@left.evaluate.to_s+@value)
		else
			$TRACE.debug 6, "in evaluate value = #{@value.inspect}"
			case @value
			when "."
				$TRACE.debug 6, "obj = #{obj.inspect}, send right = '#{@right.value.inspect}'"
				ret = obj.send(@right.value)
			when "=~"
				$TRACE.debug 6, "in =~ #{@left.evaluate(a).inspect}, #{@right.value.inspect}"
				ret = (@left.evaluate(obj) =~ @right.value) != nil
			else
				ret = eval(@left.evaluate(obj).to_s+@value+@right.evaluate(obj).to_s)
			end
		end

		$TRACE.debug 6, "returning #{ret.inspect}"
		ret
	end

	def method_missing(sym, *args)
		Query.new(".", self, sym)
	end

	def equal(other)
		
	end
	
	def to_s
		if @left.nil? && @right.nil? then
			@value.to_s
		else
			"(#@left #@value #@right)"
		end
	end
end

def Q(*args)
	Query.new(args)
end

