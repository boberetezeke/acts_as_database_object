class ObjectDatabaseModelController < ObjectDatabaseSourceCodeController
	acts_as_metadata_crud_controller ObjectDatabaseModel
=begin	
	def edit
		@model_params = {}
		@edit = ObjectDatabaseModel.find(params["id"])
		@model_params[:title] = "editing #{@edit.name}"
		@edit.content
	end

	def update
		super(false)
		redirect_to :controller => "world", :action => "main"
	end

	def new
		@model_params = {}
		@model_params[:title] = "creating new model"
		@edit = ObjectDatabaseModel.new_from_template
	end
=end

	def create
		_create(false)

		ObjectDatabaseController.new_for_name(@object.name, "ObjectDatabaseModelSuperclassController").save
		ObjectDatabaseHelper.new_for_name(@object.name).save
		redirect_to :controller => "world", :action => "main"
	end	
end
