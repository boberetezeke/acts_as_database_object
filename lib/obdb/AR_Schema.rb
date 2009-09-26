#require "obdb/acts_as_database_object"

class SchemaTable < ActiveRecord::Base
	acts_as_database_object

	link_text {|x,c| x.name}
	
	has_field :name, :type => :string
	has_many :schema_columns
end

class SchemaColumn < ActiveRecord::Base
	acts_as_database_object

	link_text {|x,c| (c.kind_of?(SchemaTable) ? "" : "#{x.schema_table.name}::") + x.name}

	belongs_to :schema_table

	has_field :name, :type => :string
	has_field :column_type, :type => :string
end

