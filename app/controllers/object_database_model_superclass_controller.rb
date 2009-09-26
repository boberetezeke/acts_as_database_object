class ObjectDatabaseModelSuperclassController < ApplicationController
	helper :object_database_model_superclass

	def show_render(do_render=false)
		$TRACE.debug 5, "ObjectDatabaseModelSuperclassController:show"
		render :template => "object_database_model_superclass/show"
	end

	def before_create
		$TRACE.debug 5, "WidgetController - create: #{params.inspect}"
		@tag_list = params["edit"].delete("tag_list")
		$TRACE.debug 5, "WidgetController - create: (after delete) #{params.inspect}"
	end

	def after_create
		@object.tag_with(@tag_list)
	end
end
