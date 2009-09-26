class ObjectDatabaseController < ObjectDatabaseSourceCode
	acts_as_database_object
	after_save :write_controller_code

	link_text {|x,c| "Controller: #{x.name}"}

TEMPLATE = <<EOT
class %sController < %s
  acts_as_metadata_crud_controller %s
end
EOT

	class << self
		def new_for_name(name, parent_class="ApplicationController")
			self.new(:content => BigString.new(TEMPLATE % [name, parent_class, name]))
		end
	end

	def name_from_content
		/class\s+(\w+)Controller/.match(self.content)[1]
	end

	def write_controller_code
		filename = "app/controllers/#{self.name.tableize.singularize}_controller.rb"
		write_source_code(filename)
	end
end
