class Event < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable
end

class HypertableWithNoOptions < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable
end

class HypertableWithOptions < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :timestamp
end

class HypertableWithCustomTimeColumn < ActiveRecord::Base
  self.table_name = "hypertable_with_custom_time_column"
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :timestamp
end

class HypertableLean < ActiveRecord::Base
  self.primary_key = "identifier"

  acts_as_hypertable skip_association_scopes: true, skip_default_scopes: true
end

class HypertableWithCustomTimeColumnAndLean < ActiveRecord::Base
  self.table_name = "hypertable_with_custom_time_column_and_lean"
  self.primary_key = "identifier"

  acts_as_hypertable time_column: :timestamp, skip_association_scopes: true, skip_default_scopes: true
end

class HypertableWithCustomTimeColumnAndLeanAndNoOptions < ActiveRecord::Base
  self.table_name = "hypertable_with_custom_time_column_and_lean_and_no_options"
  self.primary_key = "identifier"

  acts_as_hypertable skip_association_scopes: true, skip_default_scopes: true
end


class HypertableSkipAllScopes < ActiveRecord::Base
  self.table_name = "hypertable_skipping_all_scopes"
  acts_as_hypertable time_column: :timestamp, skip_association_scopes: true, skip_default_scopes: true
end

class NonHypertable < ActiveRecord::Base
end
