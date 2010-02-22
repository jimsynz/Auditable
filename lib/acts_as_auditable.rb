module MashdCc
  module Acts 
    class AuditableFilter
      def before(controller)
        if !controller.session[:current_user].nil?
          Thread.current['auditable_current_user'] = controller.session[:current_user]
        end
      end
      def after(controller)
        if !Thread.current['auditable_current_user'].nil?
          Thread.current['auditable_current_user'] = nil
        end
      end
    end
    module Auditable 

      def self.included(base)
        base.extend(ClassMethods)
      end

      class Helpers
        def self.random_method(name)
          name = "auditable_#{name}_"
          (0..14).each do |i|
            name << (('A'..'Z').to_a+('a'..'z').to_a+('0'..'9').to_a)[rand(61)]
          end
          name
        end
      end

      module ClassMethods
        def acts_as_auditable(options={})
          defaults = { 
            :using => :auditable, 
            :relation => :audits, 
            :when => [ :accessed, :modified, :saved, :created, :deleted ], 
            :except => [],
            :identity => :current_user,
            :for => [ :all ],
            :not => [],
            :log_field => :log,
            :identity_field => :identity,
          }
          options = defaults.merge(options)
          options[:when] = options[:when] - options[:except]
          do_log = Helpers.random_method("auditor")
          if options[:using].is_a? Symbol and options[:relation].is_a? Symbol
            # Define the has_many relationship for the auditable model
            self.class_eval <<-RUBY
            has_many :#{options[:relation].to_s}, :as => :#{options[:using].to_s}
            RUBY
          end
          if options[:identity].is_a? Proc
            get_identity = Helpers.random_method("get_identity")
            self.class_eval do
              define_method get_identity.to_sym do
                f = options[:identity]
                f.call
              end
            end
          elsif options[:identity] == :current_user
            get_identity = Helpers.random_method("get_identity")
            current_user = 'auditable_current_user'
            self.class_eval do 
              define_method get_identity.to_sym do
                if Thread.current[current_user].nil?
                  'Unknown user'
                elsif Thread.current[current_user].is_a? String
                  Thread.current[current_user]
                elsif Thread.current[current_user].is_a? ActiveRecord::Base
                  # try a few likely candidates before giving up.
                  model = Thread.current[current_user]
                  if model.respond_to? :login
                    model.login
                  elsif model.respond_to? :username
                    model.username
                  elsif model.respond_to? :user
                    model.user
                  elsif model.respond_to? :name
                    model.name
                  else
                    'Unknown user'
                  end
                end
              end
            end
          end
          self.class_eval <<-RUBY
            def audit(message)
              self.#{do_log}(:action => :arbitrary, :message => message)
            end
          RUBY
          if options[:when].member? :created
            m = Helpers.random_method("after_create")
            self.class_eval <<-RUBY
              after_create :#{m}

              private

              def #{m}
                self.#{do_log}(:action => :create)
              end
            RUBY
          end
          if options[:when].member? :deleted
            if self.class.instance_methods.member? "before_destroy"
              m = Helpers.random_method("before_destroy")
              self.class_eval <<-RUBY
              alias :before_destroy :#{m}

              private

              def before_destroy
                self.#{do_log}(:action => :delete)
                if self.methods.member? '#{m}'
                  #{m}
                end
              end
              RUBY
            else
              self.class_eval <<-RUBY
              private

              def before_destroy
                self.#{do_log}(:action => :delete)
              end
              RUBY
            end
          end
          if options[:when].member? :saved
            m = Helpers.random_method("after_save")
            self.class_eval <<-RUBY
              after_save :#{m}

              private

              def #{m}
                self.#{do_log}(:action => :save)
              end
            RUBY
          end
          columns = []
          if options[:for].member? :all
            columns = self.column_names()
          else
            columns = (options[:for]-options[:not]).collect do |column|
              column.to_s
            end
          end
          # remove id from the fields we audit, otherwise we wind
          # up auditing ourself (1 Infinite Loop).
          columns = columns - [ 'id' ]
          if options[:when].member? :modified
            # Catch if someone modifies :id.
            (columns + [ 'id' ]).each do |column|
              if self.class.instance_methods.member? "#{column}="
                m = Helpers.random_method("#{column}=")
                self.class_eval <<-RUBY
                alias :#{column}= :#{m}

                def #{column}=(val)
                  self.#{do_log}(:action => :modify, :column => :#{column}, :old => read_attribute(:#{column}), :new => val)
                  if self.methods.member? '#{m}'
                    #{m}(val)
                  else
                    write_attribute(:#{column}, val)
                  end
                end
                RUBY
              else
                self.class_eval <<-RUBY
                def #{column}=(val)
                  self.#{do_log}(:action => :modify, :column => :#{column}, :old => read_attribute(:#{column}), :new => val)
                  write_attribute(:#{column}, val)
                end
                RUBY
              end
            end
          end
          if options[:when].member? :accessed
            columns.each do |column|
              if self.class.instance_methods.member? column
                m = Helpers.random_method(column)
                self.class_eval <<-RUBY
                def #{column}
                  self.#{do_log}(:action => :access, :column => :#{column})
                  if self.methods.member? '#{m}'
                    #{m}
                  else
                    read_attribute(:#{column})
                  end
                end
                RUBY
              else
                self.class_eval <<-RUBY
                def #{column}
                  self.#{do_log}(:action => :access, :column => :#{column})
                  read_attribute(:#{column})
                end
                RUBY
              end
            end
          end
          self.class_eval do
            define_method do_log.to_sym do |opts|
              if !opts.is_a? Hash
                opts = {}
              end
              defaults = { :action => false }
              opts = defaults.merge(opts)
              logger.debug(opts.inspect)
              ident = eval("self.#{get_identity}()")
              log = []
              case opts[:action]
              when :create
                log << "New #{self.class.name} created by #{ident}."
              when :delete
                log << "Instance #{self.class.name}(#{read_attribute :id}) deleted by #{ident}."
              when :save
                log << "Instance #{self.class.name}(#{read_attribute :id}) saved by #{ident}."
              when :modify
                log << "Instance #{self.class.name}(#{read_attribute :id}) modified by #{ident}."
                log << "\tField #{opts[:column]} changed from #{opts[:old].inspect} to #{opts[:new].inspect}."
              when :access
                log << "Instance #{self.class.name}(#{read_attribute :id}), field #{opts[:column]}  accessed by #{ident}."
              when :arbitrary
                log << opts[:message].split("\n").first
                log << "Arbitrary audit of #{self.class.name}(#{read_attribute :id}) user #{ident}."
                opts[:message].split("\n").collect { |line| log << "\t#{line}" }
              end
              log << "\tCurrent field values are:"
              columns.each do |column|
                log << "\t\t#{column} => #{read_attribute(column.to_s).inspect}"
              end
              begin
                eval <<-RUBY
                self.#{options[:relation]}.create(:#{options[:log_field].to_s} => log * "\n", :#{options[:identity_field].to_s} => ident)
                RUBY
              rescue Exception => e
                _log = []
                _log << "Auditor: Exception while saving audit log:"
                _log << "\t#{e.message}"
                e.backtrace.each do |bt|
                  _log << bt.inspect
                end
                _log << ''
                log = _log + log
                logger.debug(log * '\n')
              end
            end
          end
          # Only if we have successfully made it to the end
          # and have installed all our helper functions do
          # we let the world know that this model is 
          # auditable.
          # This is a pretty nasty hack, but for class variables
          # seem to be shared between all models (something to do
          # with them all sharing the same base class I think).
          self.class_eval <<-RUBY
            class AuditableEnabled
            end
          RUBY
        end

        def auditable?
          begin
            self.const_get 'AuditableEnabled'
            return true
          rescue NameError
            return false
          end
        end

      end

    end
  end
end

