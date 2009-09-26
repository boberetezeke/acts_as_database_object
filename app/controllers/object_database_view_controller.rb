class ObjectDatabaseViewController < ApplicationController
	acts_as_metadata_crud_controller ObjectDatabaseView

	def show
		@model_params = {}
		super
	end
end
