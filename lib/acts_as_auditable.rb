module MashdCc
  module Acts 
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
            :identity => lambda { "Unknown user" }, 
            :for => [ :all ],
            :log_field => :log,
            :identity_field => :identity,
          }
          options = defaults.merge(options)
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
          end
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
            m = Helpers.random_method("before_destroy")
            self.class_eval <<-RUBY
              before_destroy :#{m}

              private

              def #{m}
                self.#{do_log}(:action => :delete)
              end
            RUBY
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
            columns = options[:for].collect do |column|
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
                  #{m}(val)
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
                #{m}
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
                log << "Instance #{self.class.name}(#{read_attribute :id}), field #{column}  accessed by #{ident}."
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
        end
      end
    end
  end
end

