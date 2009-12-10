require File.dirname(__FILE__) + '/lib/acts_as_auditable'
ActiveRecord::Base.send(:include, MashdCc::Acts::Auditable)
ActionController::Base.send(:append_around_filter, MashdCc::Acts::AuditableFilter.new)
