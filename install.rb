# Install hook code here

require 'ftools'

auditable_dir = File.dirname(__FILE__)
rails_dir = File.join(auditable_dir, '..', '..', '..')

puts "* Generating model and migration..."
exec "#{File.join(rails_dir, 'script', 'generate')} model audit audit_type:string audit_id:integer log:text identity:string"

puts "* Making model polymorphic..."
model = File.open(File.join(rails_dir,'app','models','audit.rb'), 'w')
model.puts 'class Audit < ActiveRecord::Base'
model.puts '  belongs_to :auditable, :polymorphic => true'
model.puts 'end'
model.close

puts "* You probably want to run rake db:migrate now."

puts "* Done."
