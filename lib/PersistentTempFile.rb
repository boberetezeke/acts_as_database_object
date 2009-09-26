require "my/mytime"

class PersistentTempFile
	def initialize(location, extension)
		@location = location
		@extension = extension
	end

	def create
		uniqueName = Time.current.strftime "%d%m%y-%H%M%S"
		srand Time.current.usec
		loop do
			@tempfile = sprintf "#{@location}-%s-%d.#{@extension}", uniqueName, rand(1000)
			break if !FileTest.exist?(@tempfile)
		end

		@tempfile
	end

	def delete
		File.delete(@tempfile)
	end
end

