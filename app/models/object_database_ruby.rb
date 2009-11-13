class ObjectDatabaseRuby < ObjectDatabaseSourceCode
	acts_as_database_object do
		has_field :content, :type => :text, :options => {:html_converter =>  proc{|b, x| "<pre name=\"code\" class=\"ruby:nocontrols\">" + CGI.escapeHTML(x) + "</pre>"}}
		has_field :relative_path
	end

	serialize :content
	after_save :write_model_code
	
	link_text {|x,c| "Ruby: #{x.full_name}"}

TEMPLATE=<<EOT
# insert ruby code below
EOT

	class << self
		def new_from_template
			ObjectDatabaseRuby.new(:content => TEMPLATE)
		end
	end

	def name_from_content
		self.name
	end

	#
	# make sure the path to the file exists
	#
	def make_relative_path
		if self.relative_path then
			segments = self.relative_path.split(/\//)
			path = "lib"
puts "segments = #{segments.inspect}"
			segments.each do |seg|
				path += "/" + seg
puts "path = #{path}"
				begin
					stat = File.stat(path)
					if !stat.directory? then
						return false
					end
				rescue Errno::ENOENT
puts "path not found, make dir #{path}"
					Dir.mkdir(path) rescue nil
				end
			end
		end

		return true
	end

	def full_name
		((self.relative_path && !self.relative_path.empty?) ? self.relative_path + "/" : "") +
			self.name
	end

	def write_model_code
		filename = "lib/#{self.full_name}.rb"
		if make_relative_path then
			write_source_code(filename)
		else
			# FIXME: what to do?
		end
	end
end
