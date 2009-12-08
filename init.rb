require File.dirname(__FILE__) + '/lib/acts_as_auditable'
ActiveRecord::Base.send(:include, MashdCc::Acts::Auditable)
