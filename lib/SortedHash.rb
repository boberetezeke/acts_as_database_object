
class SortedHash < Hash
	def initialize
		super
	end

	def to_a
		super.to_a.sort{|a,b| a[0]<=>b[0]}
	end

	def each
		self.to_a.each{|c| yield c}
	end

	def each_key
		self.keys.each{|k| yield k}
	end

	def each_value
		values.each{|v| yield v}
	end

#	def [](*args)
#		self.to_a[*args]
#	end

	def keys
		super.sort
	end

	def values
		self.map{|a,b| b}
	end
end





