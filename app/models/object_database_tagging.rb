class ObjectDatabaseTagging < ActiveRecord::Base 
  acts_as_database_object do
	  belongs_to :object_database_tag
	  belongs_to :taggable, :polymorphic => true
	  has_field :taggable_type
  end

  # If you also need to use <tt>acts_as_list</tt>, you will have to manage the tagging positions manually by creating decorated join records when you associate Tags with taggables.
  # acts_as_list :scope => :taggable

  # This callback makes sure that an orphaned <tt>Tag</tt> is deleted if it no longer tags anything.
  def after_destroy
    tag.destroy_without_callbacks if tag and tag.taggings.count == 0
  end    
end
