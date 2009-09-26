require "ftools"

class ObjectDatabaseConfigurationController < ApplicationController
	acts_as_metadata_crud_controller ObjectDatabaseConfiguration

	def edit
		configurations = ObjectDatabaseConfiguration.find(:all, params["id"])
		if configurations.empty? then
			ObjectDatabaseConfiguration.new.save
		end

		super
	end

	def update
		val = super
		
		config = ObjectDatabaseConfiguration.find(1)
		Dir[File.join(config.data_store_path.gsub(/\\/, "/"), "*_Store.rb")].each do |fname|
			bname = File.basename(fname)
			bname_match = /(.*)(\.rb)/.match(bname)
			bname_class_name = bname_match[1].camelize
			dest_fname = "app/models/#{bname}"
			if FileTest.exist?(dest_fname) then
				# if the file being pulled in is newer than the file we have
				if File.stat(fname).mtime > File.stat(dest_fname).mtime then
					#data_store = ObjectDatabaseDataStore.find(:first, "name='#{bname_class_name}'")
					File.copy(fname, dest_fname)
				end
			else
				File.copy(fname, dest_fname)
				ObjectDatabaseDataStore.new(:name => bname_class_name).save
				ObjectDatabaseController.new_for_name(bname_class_name, "StoreController").save
				ObjectDatabaseHelper.new_for_name(bname_class_name).save
			end
		end
		
		val
	end
end

