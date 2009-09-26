class ObjectDatabaseSourceCodeController < ApplicationController
	acts_as_metadata_crud_controller ObjectDatabaseSourceCode

	def new
		@model_params = {
			:title => "creating new #{params['object_type']}",
			:members_to_display => [:content]
		}
		modify_new_model_params(@model_params)
		
		@edit = crud_model.new_from_template
		_new
	end

	protected

	# stub to be over-ridden	
	def modify_new_model_params(model_params)
	end
end
