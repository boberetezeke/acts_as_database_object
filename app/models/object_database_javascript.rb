class ObjectDatabaseJavascript < ObjectDatabaseSourceCode
	acts_as_database_object

	serialize :content
	after_save :write_model_code

	#has_field :content, :type => :text, :options => {:html_converter =>  proc{|x| "<div class=\"javascript\">" + Syntax::Convertors::HTML.for_syntax("javascript").convert(x) + "</div>"}}
	has_field :content, :type => :text, :options => {:html_converter =>  proc{|b, x| "<pre name=\"code\" class=\"javascript:nocontrols\">" + CGI.escapeHTML(x) + "</pre>"}}
	
	link_text {|x,c| "Javascript: #{x.name}"}

TEMPLATE=<<EOT
// insert javascript code below
EOT

	class << self
		def new_from_template
			ObjectDatabaseJavascript.new(:content => TEMPLATE)
		end
	end

	def name_from_content
		self.name
	end

	def write_model_code
		filename = "public/javascripts/#{self.name}.js"
		write_source_code(filename)
	end
end
