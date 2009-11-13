class ObjectDatabaseSourceCode < ActiveRecord::Base
	acts_as_database_object do
		has_field :name
		has_field :is_plugin_source_code, :type => :boolean, :default => false

		# CGI.escapeHTML(x)
		#has_field :content, :type => :text, :options => {:html_converter =>  proc{|x| "<div class=\"ruby\">" + Syntax::Convertors::HTML.for_syntax("ruby").convert(x) + "</div>"}}
		has_field :content, :type => :text, :options => {:html_converter =>  proc{|b, x| "<pre name=\"code\" class=\"ruby:nocontrols\">" + CGI.escapeHTML(x) + "</pre>"}}
	end

	before_save :update_name
	before_save :set_source_code_has_changed

	def name_from_content
		/class\s+(\w+)/.match(self.content)[1]
	end

	def update_name
		self.name = name_from_content unless self.is_plugin_source_code
	end

	def write_source_code(filename)
		return if self.is_plugin_source_code

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
