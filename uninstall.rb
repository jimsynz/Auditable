# Uninstall hook code here

require 'ftools'

auditable_dir = File.dirname(__FILE__)
rails_dir = File.join(auditable_dir, '..', '..', '..')

puts '* Generating removal migration...'
migration = File.open(File.join(rails_dir,'db','migrate',"#{Time.now.strftime('%Y%m%d%H%M%S')}_drop_audits.rb"), 'w')
migration.puts 'class DropAudits < ActiveRecord::Migration'
migration.puts '  def self.up'
migration.puts '    drop_table :audits'
migration.puts '  end'
migration.puts ''
migration.puts '  def self.down'
migration.puts '    create_table :audits do |t|'
migration.puts '      t.string :auditable_type'
migration.puts '      t.integer :auditable_id'
migration.puts '      t.text :log'
migration.puts '      t.string :identity'
migration.puts ''
migration.puts '      t.timestamps'
migration.puts '    end'
migration.puts '  end'
migration.puts 'end'
migration.close
puts '* Removing model audit.rb'
[ [ 'app', 'models', 'audit.rb' ], [ 'test', 'unit', 'audit_test.rb' ], [ 'test', 'fixtures', 'audits.yml' ] ].each do |file|
  file = File.join(rails_dir, *file)
  puts "     exists  #{file}"
  if File.exists? file
    puts "     remove  #{file}"
    File.safe_unlink file
  end
end
puts "* Done."
