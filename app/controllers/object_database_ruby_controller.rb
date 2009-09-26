class ObjectDatabaseRubyController < ObjectDatabaseSourceCodeController
	acts_as_metadata_crud_controller ObjectDatabaseRuby

	def modify_new_model_params(model_params)
		model_params[:members_to_display].insert(0, :relative_path)
		model_params[:members_to_display].insert(0, :name)
	end
end
