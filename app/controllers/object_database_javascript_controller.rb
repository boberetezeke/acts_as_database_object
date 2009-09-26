class ObjectDatabaseJavascriptController < ObjectDatabaseSourceCodeController
	acts_as_metadata_crud_controller ObjectDatabaseJavascript

	def modify_new_model_params(model_params)
		model_params[:members_to_display].insert(0, :name)
	end
end
