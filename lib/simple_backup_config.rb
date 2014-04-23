require "simple_backup/version"

module SimpleBackup
  class BackupConfig
  
    attr_accessor :app_name, :backup_dir, :bin_dir, :excluded_tables, :keep_all_backup_last, :keep_one_backup_each
  
    def initialize()
      self.set_default_values
  
      backups_rb_path = "#{Rails.root}/config/backups.rb"
      content = File.open(backups_rb_path, 'r').read
      self.instance_eval(content, backups_rb_path)
    end
  
    def set_default_values()
      @keep_all_backup_last = 1.month
      @keep_one_backup_each = :month #:year, :month or :week
    end
  end
end
