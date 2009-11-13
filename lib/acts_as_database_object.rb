# Copyright (c) 2005 Rick Olson
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
require "my/mytime"
require "SimpleTrace"
require "obdb/AR_LastDataStoreObjects"
require "obdb/AR_DeletedObjects"
require "obdb/AR_ObjectDatabaseFind"

module ActiveRecord #:nodoc:
	module Acts #:nodoc:
		# Specify this act if you want to save a copy of the row in a versioned table.  This assumes there is a 
		# versioned table ready and that your model has a version field.  This works with optimisic locking if the lock_version
		# column is present as well.
		#
		# The class for the versioned model is derived the first time it is seen. Therefore, if you change your database schema you have to restart
		# your container for the changes to be reflected. In development mode this usually means restarting WEBrick.
		#
		#   class Page < ActiveRecord::Base
		#     # assumes pages_versions table
		#     acts_as_database_object do
		#       has_field :field_name
		#       has_many :comments
		#     end
		#   end
		#
		# Example:
		#
		#   page = Page.create(:title => 'hello world!')
		#   page.version       # => 1
		#
		#   page.title = 'hello world'
		#   page.save
		#   page.version       # => 2
		#   page.versions.size # => 2
		#
		#   page.revert_to(1)  # using version number
		#   page.title         # => 'hello world!'
		#
		#   page.revert_to(page.versions.last) # using versioned instance
		#   page.title         # => 'hello world'
		#
		# See ActiveRecord::Acts::Versioned::ClassMethods#acts_as_versioned for configuration options
		module AsDatabaseObject
      	def self.included(base) # :nodoc:
				base.extend ClassMethods
				base.extend SameTable_LastDataStoreObjects_acts_as_do_mods_class_methods
				base.extend SameTable_DeletedObjects_acts_as_do_mods_class_methods
 			end

 			module ClassMethods
				# == Configuration options
				#
				# * <tt>version_column</tt> - name of the column in the model that keeps the version number (default: version)
				#
				#
				#
				# * <tt>if_changed</tt> - Simple way of specifying attributes that are required to be changed before saving a model.  This takes
				#   either a symbol or array of symbols.
				#
				def acts_as_database_object(options = {})
					# we rely on acts_with_metadata
					class_eval do
						opts = {}
						if self.superclass == ActiveRecord::Base then
							opts = {:re_initialize => true, :excluded_columns => [:version]}
						end
						acts_with_metadata opts
					end
					
					# allow the class to define all of its fields
					yield if block_given?					

					# we rely on modifying find and ferret
					class_eval do
						extend ObjectDatabaseFind
						acts_as_ferret(:fields => self.declared_members.map{|x| x.field_name}) unless $testing
					end
					
					# don't allow multiple calls
					already_included = self.included_modules.include?(ActiveRecord::Acts::AsDatabaseObject::ActMethods)

					$TRACE.debug 5, "acts_as_database_object: in class #{self}, included = #{already_included}"

					class_eval do
						attr_accessor :changed_attributes_aado
						@includes_acts_as_database_object = true
					end
					
					unless already_included 
						class_eval do
							include ActiveRecord::Acts::AsDatabaseObject::ActMethods
							include SameTable_LastDataStoreObjects_acts_as_database_object_object_methods
							cattr_accessor :version_column, :watched_attributes
							attr_accessor :changed_attributes_aado
							attr_accessor :track_changed_attributes
						end

						self.version_column = options[:version_column] || 'version'
						#self.watched_attributes = options[:if_changed]
						self.watched_attributes = []
					end
						
					class_eval do
						# polymorphic association with database_object
						has_one :database_object, :as => :databaseable_object

			
						# AR_LastDataStoreObjects
						belongs_to :base_database_object, 	:class_name => "DatabaseObject",
																		:foreign_key => "base_database_object_id",
																		:internal_use_only => true

						# this is after_create instead of before_create because observers of change need to have the
						# object's id -- there may be a better way around this.
						after_create :save_version_on_create
						after_update :save_version
						after_create :clear_changed_attributes, :modify_observers_on_create
						after_update :clear_changed_attributes
						before_destroy :handle_object_destroy

						#unless options[:if_changed].nil?
						#	self.track_changed_attributes = true
						#	options[:if_changed] = [options[:if_changed]] unless options[:if_changed].is_a?(Array)
						#	options[:if_changed].each do |attr_name|
						#		$TRACE.debug 5, "defining method #{attr_name}="
						#		add_attr_writer(attr_name)
						#	end
						#end
					end # class_eval
				end # def acts_as_database_object(options = {})
				
				#
				# add an add/remove filter for either (:after_add or :after_remove)
				#
				def add_add_remove_filter(filter_name, action_str, after_hash, options)
					p = proc{|has_many_object, belongs_to_object| 
							field_name = belongs_to_object.class.members.select{|y| y.primary_key_name == after_hash[:reflection].primary_key_name}[0].field_name
							$TRACE.debug 5, "acts_as_incrementally_versioned: belongs to object: #{belongs_to_object.id} was #{action_str} has many object: #{has_many_object.id} on"
							$TRACE.debug 5, "field #{after_hash[:reflection].primary_key_name} and member = #{field_name}"
							belongs_to_object.record_relationship_change(field_name, :add, has_many_object.id)
						}
					after_filter = options[filter_name]
					if after_filter then
						if after_filter.kind_of?(Array) then
							after_add.push(p)
						else
							options[filter_name] = [after_filter, p]
						end
					else
						options[filter_name] = p
					end
				end

				#
				# add a specialized attr_reader to handle the issue of serialized text fields (which they all are as
				# we use them for BigString). The serialization/deserialization process uses YAML and YAML::load("")
				# returns false instead of an empty string.
				#
				def add_attr_reader(attr_name, column_type)
=begin
					if column_type == :text then
						define_method("#{attr_name}") do
							value = read_attribute(attr_name.to_s)
							# if the value de-serialized is false, it means a ""
							if value == false || value == 0 then
								value = ""
							end
							value
						end
					end
=end
				end
				
				def add_attr_writer(attr_name)
					#eval("alias :old_#{attr_name}= :#{attr_name}=")
					define_method("#{attr_name}=") do |value|
						$TRACE.debug 9, "setting #{attr_name} on #{self} to #{value.inspect}"
						$TRACE.debug 9, "getting #{attr_name} as #{self.send(attr_name).inspect}"
						$TRACE.debug 9, "self.changed?(attr_name) = #{self.changed?(attr_name)}"
						$TRACE.debug 9, "track_changed_attributes = #{self.track_changed_attributes}"
						$TRACE.debug 9, "before changed_attributes = #{changed_attributes_aado.inspect}"
						$TRACE.debug 9, "type = #{self.class.members[attr_name].field_type}"
						#puts "setting #{attr_name} on #{self.inspect} to #{value}"
						#(self.changed_attributes ||= []) << Change.new(attr_name, value, self.send(attr_name)) unless self.changed?(attr_name) or self.send(attr_name) == value
						self.track_changed_attributes = true if self.track_changed_attributes == nil
						if DatabaseObject.track_changed_attributes && self.track_changed_attributes then
							$TRACE.debug 9, "modifying changed_attributes"
							(self.changed_attributes_aado ||= []) << Change.new(attr_name, self.send(attr_name), value) unless self.send(attr_name) == value
						end
						$TRACE.debug 0, "after changed_attributes = #{changed_attributes_aado.inspect}"

						write_attribute(attr_name.to_s, value)
					end
				end

				def add_belongs_to_attr_writer(reflection, association_proxy_class)
					$TRACE.debug 5, "add_belongs_to_attr_writer: adding #{reflection.name}= method"
					define_method("#{reflection.name}=") do |new_value|
						association = instance_variable_get("@#{reflection.name}")
						association_was_nil = association.nil?
						if association.nil?
							association = association_proxy_class.new(self, reflection)
						end
						$TRACE.debug 5, "add_belongs_to_attr_writer: writing #{new_value} to #{reflection.name}, #{reflection.primary_key_name}"
						if new_value then
							new_id = new_value.attributes["id"]
						else
							new_id = nil
						end
						$TRACE.debug 5, "add_belongs_to_attr_writer: reading value of #{reflection.name} on #{self.inspect} is #{self.send(reflection.name)}"
						old_value = self.send(reflection.name)
						if old_value then
							$TRACE.debug 5, "add_belongs_to_attr_writer: old value is #{old_value.inspect} attributes = #{old_value.attributes.inspect}"
							old_id = old_value.attributes["id"] # unless association_was_nil
						end
						$TRACE.debug 5, "add_belongs_to_attr_writer: #{old_id} to #{new_id}"
						
						(self.changed_attributes_aado ||= []) << Change.new(reflection.name, old_id, new_id) unless old_id == new_id

						association.replace(new_value)

						unless new_value.nil?
							instance_variable_set("@#{reflection.name}", association)
						else
							instance_variable_set("@#{reflection.name}", nil)
							return nil
						end

						association
					end
				end
			
				def has_many(sym, options={})
					if @includes_acts_as_database_object then
						$TRACE.debug 9, "in acts_as_database_object#has_many(#{sym}, #{options.inspect})"

						after_hash = {}	# this is referenced in the filter proc to get the reflection information that is only
												# available after the super call is made
						unless @add_remove_filters_added 
							@add_remove_filters_added = true
							add_add_remove_filter(:after_add, "added to", after_hash, options)
							add_add_remove_filter(:after_remove, "removed from", after_hash, options)
						end
						
						super(sym, options)

						# fill in the reflection information
						after_hash[:reflection] = self.reflect_on_association(sym)
					else
						super(sym, options)
					end
				end

				def belongs_to(sym, options={})
					$TRACE.debug 9, "in acts_as_database_object#belongs_to(#{sym}, #{options.inspect})"
					super(sym, options)
					#belongs_to(sym, options)

					return unless @includes_acts_as_database_object
					
					reflection = create_belongs_to_reflection(sym, options)
					$TRACE.debug 5, "in acts_as_incrementally_versioned#belongs_to before call to add_belongs_to_attr_writer"
					add_belongs_to_attr_writer(reflection, ActiveRecord::Associations::BelongsToAssociation)
				end

				def has_field(sym, options={})
					super(sym, options)

					return unless @includes_acts_as_database_object

					if options[:type] == :text then
						self.serialize(sym)
					end

					unless options[:exclude]
						$TRACE.debug 5, "defining method #{sym}="
						self.watched_attributes += [sym]
						add_attr_writer(sym)
						add_attr_reader(sym, options[:type])
					end						
				end

=begin
				def findx(find_method, options={})
					$TRACE.debug 5, "findx(before): find_method=#{find_method}, options=#{options.inspect}"
					find_method, options = last_store_object_find_mod(find_method, options)
					$TRACE.debug 5, "findx(after-last_store_object_find_mod): find_method=#{find_method}, options=#{options.inspect}"
					find_method, options = deleted_objects_find_mod(find_method, options)
					$TRACE.debug 5, "findx(after-deleted_objects_find_mod): find_method=#{find_method}, options=#{options.inspect}"
					find(find_method, options)
					#[find_method, options]
				end
				def method_missing(sym, *args)
puts "method_missing: sym = #{sym}"
					if sym.to_s == "find" then
						find_method, options = *args
						find_method, options = findx(find_method_options)
						find(sym, find_method, options)
					else
						super(sym, *args)
					end
				end
=end				
			end #ClassMethods
			
			module ActMethods
				def self.included(base) # :nodoc:
					base.extend ClassMethods
				end

	# this is a hack so that when we load the models up initially acts_as_ferret won't throw an 
	# exception because the following method doesn't exist on ObjectDatabaseModel (which it doesn't)
	# I think that this is because of STI and that ObjectDatabaseCommandHandler and ObjectDatabaseModel
	# share the same table
				def method_missing(sym, *args)
					puts "method_missing: sym = #{sym}"
					if sym.to_s =~ /to_ferret$/ then
						puts "************************** REJECTED **************************"
						return ""
					else
						super(sym, *args)
					end
				end
	#def prefix_to_ferret
		#return ""
	#end

				def initialize(*args)
					self.track_changed_attributes = true
					self.changed_attributes_aado = []

					super(*args)
					
					require "obdb/AR_DatabaseObject"	# its here because of a circular reference problem
					self.database_object = DatabaseObject.create_do(self.class, self.id, self)
				end

				def ==(other)
					return false unless other.kind_of?(self.class)
					self.class.watched_attributes.each do |attr|
						if self.class.members[attr].field_type != :belongs_to then
							return false if read_attribute(attr) != other.send(attr)
						end
					end

					return true
				end

				def dup
					new_object = self.class.new	# FIXME: need to do it without args 
					new_object.stop_recording_changes
					self.class.watched_attributes.each do |attr|
						new_object.send("#{attr}=", read_attribute(attr))
					end
					new_object.start_recording_changes

					new_object.database_object = self.database_object.dup
					
					new_object
				end

				def class_name
					self.class.to_s
				end

				def database_id
					return self.attributes["id"] if self.attributes["id"]
					return "0x%8.8x" % [self.object_id]
				end

				def gid
					self.database_object.attributes["id"]
				end
				
				def history
					self.changed_attributes_aado ||= []
					$TRACE.debug 5, "calling history, changed_attributes = #{changed_attributes_aado.inspect}"
					get_database_object.history(changed_attributes_aado)
				end

				alias changes history
				
				def get_version(*args)
					#self.changed_attributes ||= []
					get_database_object.get_version(self, changed_attributes_aado, *args)
				end

				def has_changed_since(*args)
					get_database_object.has_changed_since(self, *args)
				end

				def generate_member_changes(other_ar_object)					
					member_changes = MemberChanges.new
					self.class.members.each do |member|
						self_value = self.send(member.field_name)
						other_value = other_ar_object.send(member.field_name)
						$TRACE.debug 5, "for field (#{member.field_name}) comparing self_value (#{self_value.inspect}) with other_value (#{other_value.inspect})"
						if self_value != other_value then
							#memberChanges.push(MemberChange.new(member, nil, ourValue, otherValue))
							member_change = MemberChange.new(member.field_name, nil, self_value.generate_changes(other_value))
							$TRACE.debug 5, "member_change created: #{member_change.inspect}"
							member_changes.push(member_change)
						end
					end
					
					return member_changes 
				end

				def apply_member_changes(*args)
					get_database_object.apply_member_changes(self, *args)
				end
				
				def num_versions
					history.size
				end
=begin
				def set_dbID(store, id_str)
					#get_database_object.set_dbID(store, id_str)
				end

				def dbID(store)
					if dobj = get_database_object then
						dobj.dbID(store)
					else
						get_last_data_store_object_dbID
					end
				end
=end

				# Saves a version of the model if applicable
				def save_version
					$TRACE.debug 9, "save_version: at beginning: #{self.inspect}"
					self.changed_attributes_aado ||= []
					$TRACE.debug 5, "save_version, changed_attributes = #{changed_attributes_aado.inspect}"
					#save_version_on_create if save_version?
					if (dobj = get_database_object) && !changed_attributes_aado.empty? then
						dobj.save_version(changed_attributes_aado)
					end
				end
			  
				# Saves a version of the model in the versioned table.  This is called in the after_save callback by default
				def save_version_on_create
					$TRACE.debug 9, "save_version_on_create, changed_attributes = #{changed_attributes_aado.inspect}"
					if self.database_object then
						self.database_object.save_version_on_create(self.id)
						
						save_version if save_version?
					end
				end

			  	# If called with no parameters, gets whether the current model has changed and needs to be versioned.
			  	# If called with a single parameter, gets whether the parameter has changed.
			  	def changed?(attr_name = nil)
					self.changed_attributes_aado ||= []
			   	attr_name.nil? ?
			    		(changed_attributes_aado and changed_attributes_aado.length > 0) :
			   		(changed_attributes_aado and changed_attributes_aado.include?(attr_name.to_s))
			  	end
			          
			  	# Checks whether a new version shall be saved or not.  Calls <tt>version_condition_met?</tt> and <tt>changed?</tt>.
			  	def save_version?
			  		changed?
			  	end

				#
				# record that field_name has changed in a change_type (:add, :remove) way with change_id (the id that was :add or :remove)
				#
				def record_relationship_change(field_name, change_type, change_id)
					self.changed_attributes_aado ||= []
					if change_type == :add then
						last_change = self.changed_attributes_aado.last
						# if the last change was for this same field
						if last_change && last_change.name == field_name then
							# we combine the removal and add into one replace change
							self.changed_attributes_aado.delete_at(self.changed_attributes_aado.size-1)
							self.changed_attributes_aado << Change.new(field_name, last_change.old_value, change_id)
						else
							# its just an add
							self.changed_attributes_aado << Change.new(field_name, nil, change_id)
						end
					elsif change_type == :remove then
						self.changed_attributes_aado << Change.new(field_name, change_id, nil)
					end
			  	   $TRACE.debug 5, "record_relationship_change: #{self.class}:#{self.id}: changed_attributes = #{changed_attributes_aado.inspect}"
				end

				# these need to be implemented ----------------------------V
				def stop_recording_changes
					@track_changed_attributes = false
				end

				def start_recording_changes
					@track_changed_attributes = true
				end

				def clear_history(num_changes)
				end
				# these need to be implemented ----------------------------^
				

			 	#
			  	# clears current changed attributes.  Called after save.
			  	#
			  	def clear_changed_attributes
			  		$TRACE.debug 5, "clear_changed_attributes"
			   	self.changed_attributes_aado = []
			  	end

				#
				# handle object destruction
				#
				def handle_object_destroy
					# copy to object to safe place so it doesn't get destroyed
				end

				#
				# observer functions
				#
				def get_observer_list
					@@observers ||= {}
					id = self.attributes["id"] || "#{self.object_id}"

					
					@@observers[id] ||= []
					$TRACE.debug 9, "getting observer for id = #{id} observers = #{@@observers[id].inspect}"
					@@observers[id]
				end
				
				def add_observer(observer)
					@@observers ||= {}
					$TRACE.debug 9, "add_observer(before): #{@@observers.inspect}"
					get_observer_list.push(observer)

					#$TRACE.debug 5, "adding observer #{observer.inspect} for #{self.object_id} and #{self.attributes['id']}"
					$TRACE.debug 9, "add_observer(after): #{@@observers.inspect}"
				end

				def delete_observer(observer)
					get_observer_list.delete(observer) if defined?(@observers)
				end

				def delete_observers
					get_observer_list.clear if defined? @observers
				end

				def get_and_delete_observers
					o = get_observer_list
					get_observer_list.clear
					o
				end

				def set_observers(observers)
					get_observer_list.replace(observers)
				end

				def notify_observers(*args)
					$TRACE.debug 5, "notifying observers with #{args} for #{self.object_id} and #{self.attributes['id']}"
					get_observer_list.each {|v| v.on_observed_change(*args)}
				end

				#
				# move observers from observing by object id to by id
				#
				def modify_observers_on_create		
					@@observers ||= {}
					$TRACE.debug 9, "modify_observers_on_create(before): #{@@observers.inspect}"
					
					object_id_key = "#{self.object_id}"
					$TRACE.debug 5, "modify_observers_on_create: for #{object_id_key} and #{self.attributes['id']}"
					if @@observers.has_key?(object_id_key) then
						observers = @@observers[object_id_key]
						$TRACE.debug 9, "modify_observers_on_create: found key, observers = #{observers.inspect}"
						@@observers.delete(object_id_key)
						@@observers[self.attributes["id"]] = observers
					end
					$TRACE.debug 9, "modify_observers_on_create(after): #{@@observers.inspect}"
				end
				
			 	protected

				#
				# get the database object associated with this object
				#
				def get_database_object
					$TRACE.debug 5, "getting database object #{self.database_object} for object #{self.class}:#{self.id}, called by #{caller[0]}"
					self.database_object
				end
			 	
			end

			private

			#
			# class to keep track of attribute changes until they are saved to disk
			#
			class Change
				attr_reader :name, :old_value, :new_value, :time
				def initialize(name, old_value, new_value)
					@name = name
					@new_value = new_value
					@old_value = old_value
					@time = Time.current
				end

				def to_s
					"#{name}: OLD: #{@old_value}, NEW: #{@new_value}"
				end
			end		
    	
		end
	end
end

ActiveRecord::Base.class_eval { include ActiveRecord::Acts::AsDatabaseObject }


