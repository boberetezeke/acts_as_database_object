class ObjectDatabaseView < ObjectDatabaseSourceCode
	acts_as_database_object do
		has_field :controller
	end

	validates_presence_of :controller

	after_save :write_view_code

	link_text {|x,c| "View: #{x.name}"}

TEMPLATE=<<EOT
<h2>XX view</h2>
EOT

#/

	class << self
		def new_from_template
			ObjectDatabaseView.new(:content => TEMPLATE)
		end
	end

	def update_name
		# nothing to do here as we can't get the name from the content
	end
	
	def write_view_code
		Dir.mkdir "app/views/#{self.controller.tableize.singularize}" rescue nil
		filename = "app/views/#{self.controller.tableize.singularize}/#{self.name}.rhtml"
		write_source_code(filename)
	end
end
