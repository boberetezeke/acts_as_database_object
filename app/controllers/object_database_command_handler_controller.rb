class ObjectDatabaseCommandHandlerController < ObjectDatabaseSourceCodeController
	acts_as_metadata_crud_controller ObjectDatabaseCommandHandler

	def modify_new_model_params(model_params)
		model_params[:members_to_display] = [:prefix] + model_params[:members_to_display]
	end
end
