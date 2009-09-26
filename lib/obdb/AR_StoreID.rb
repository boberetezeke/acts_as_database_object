class StoreID < ActiveRecord::Base
	belongs_to :database_object

	def <=>(other)
		raise "<=> can only be used to compare against other StoreID's, not (#{other.class})" unless other.kind_of?(StoreID)
		return self.name <=> other.name
	end
end

