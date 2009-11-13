class ObjectDatabaseModel < ObjectDatabaseSourceCode
	acts_as_database_object do
	end

	serialize :content
	after_save :write_model_code
	link_text {|x,c| "Model: #{x.name}"}

TEMPLATE=<<EOT
class XX < ActiveRecord::Base
  acts_as_database_object

  #has_field :fieldname
	
  #link_text {|x,c| x.fieldname}
end
EOT

	class << self
		def new_from_template
			ObjectDatabaseModel.new(:content => TEMPLATE)
		end
	end
	
	def write_model_code
		filename = "app/models/#{self.name.tableize.singularize}.rb"
		write_source_code(filename)
	end
end
