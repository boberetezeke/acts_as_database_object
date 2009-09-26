require "obdb/AR_SimpleChange"
#require "obdb/ArrayChange"

class NilClass
	include SimpleChangeMixin
end

class Fixnum
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			str.to_i
		end

		def from_val(val)
			val.to_s
		end
	end
end

class Integer
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			str.to_i
		end

		def from_val(val)
			val.to_s
		end
	end
end

class Float
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			str.to_f
		end

		def from_val(val)
			val.to_s
		end
	end
end

class String
	include SimpleChangeMixin

	class << self
		def from_s(str)
			return str.dup
		end

		def from_val(val)
			return val.dup
		end
	end
end

class FalseClass
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			if str == "true" then
				return true
			else
				return false
			end
		end

		def from_val(val)
			if val then
				return "true"
			else
				return "false"
			end
		end
	end
end

class TrueClass
	include SimpleChangeMixin

	class << self
		def from_s(str)
			if str == "true" then
				return true
			else
				return false
			end
		end

		def from_val(val)
			if val then
				return "true"
			else
				return "false"
			end
		end
	end
end

class Time
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			return Time.now
		end

		def from_val(val)
			val.to_s
		end
	end
end

class Symbol
	include SimpleChangeMixin
	
	class << self
		def from_s(str)
			return eval(":#{str}")
		end

		def from_val(val)
			val.to_s
		end
	end
end

class Array
	class << self
		def from_s(str)
			return eval(str)
		end

		def from_val(val)
			val.to_s
		end
	end

	def generate_changes(other)
		ArrayChange.new(self, other)
	end
end


