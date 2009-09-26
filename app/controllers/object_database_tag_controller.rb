class ObjectDatabaseTagController < ApplicationController
	acts_as_metadata_crud_controller ObjectDatabaseTag

	def list
		members_to_display :name
		_list
	end
end
