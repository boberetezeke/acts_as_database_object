class ObjectDatabaseEnteredCommand < ActiveRecord::Base
	acts_as_database_object

	has_field :command
end
