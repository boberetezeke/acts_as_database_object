class ObjectDatabaseSourceCode < ActiveRecord::Base
	acts_as_database_object
	has_field :name

	before_save :update_name
	before_save :set_source_code_has_changed

	# CGI.escapeHTML(x)
	#has_field :content, :type => :text, :options => {:html_converter =>  proc{|x| "<div class=\"ruby\">" + Syntax::Convertors::HTML.for_syntax("ruby").convert(x) + "</div>"}}
	has_field :content, :type => :text, :options => {:html_converter =>  proc{|b, x| "<pre name=\"code\" class=\"ruby:nocontrols\">" + CGI.escapeHTML(x) + "</pre>"}}

	def name_from_content
		/class\s+(\w+)/.match(self.content)[1]
	end

	def update_name
		self.name = name_from_content
	end

	def write_source_code(filename)
		#puts "-----------------------------------------------------------"
		#puts filename
		#puts "-----------------------------------------------------------"
		#puts self.content.x
		#puts "-----------------------------------------------------------"
		File.open(filename, "w") {|f| f.write self.content}
	end

	def set_source_code_has_changed
		ActionController::Dispatcher.force_application_cleanup
	end
end
