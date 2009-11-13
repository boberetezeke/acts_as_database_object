class ObjectDatabaseEnteredCommand < ActiveRecord::Base
	acts_as_database_object do

		has_field :command
	end
end
