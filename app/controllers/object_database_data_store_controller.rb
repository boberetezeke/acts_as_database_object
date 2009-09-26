class ObjectDatabaseDataStoreController < ObjectDatabaseModelController
	acts_as_metadata_crud_controller ObjectDatabaseDataStore

	def new_instance
		#render :text => params.inspect
		redirect_to :controller => params["data_stores"].tableize.singularize, :action => "new"
	end

	def list
		@model_params[:list_members] = [:name]
		_list
	end

	def show
		redirect_to :controller => "world", :action => "design", :type => "data_store",  :id => params["id"]
	end

	def create
		_create(false)

		ObjectDatabaseController.new_for_name(@object.name, "StoreController").save
		ObjectDatabaseHelper.new_for_name(@object.name).save
		redirect_to :controller => "world", :action => "main"
	end	

end

