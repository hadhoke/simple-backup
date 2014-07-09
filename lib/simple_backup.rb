require "simple_backup/version"
require "simple_backup_config"

module SimpleBackup
  class BackupHandler
    ENV_SHORTCUTS = {'dev'  => 'development',
                     'prod' => 'production'}
  
    def initialize(env_name)
      @config = BackupConfig.new
  
      @bin_dir              = @config.bin_dir
      @identifier           = @config.identifier
      @app_name             = @config.app_name
      @backup_dir           = @config.backup_dir
      @excluded_tables      = @config.excluded_tables
      @keep_one_backup_each = @config.keep_one_backup_each
      @keep_all_backup_last = @config.keep_all_backup_last
  
      env_name    = ENV_SHORTCUTS.fetch(env_name, env_name)
      @env        = self.env(env_name)
      @host       = @env['host']
      @port       = @env['port'] || '5432'
      @username   = @env['username']
      @password   = @env['password']
      @database   = @env['database']
    end
  
    def env(env_name)
      available_env = YAML.load_file("#{Rails.root}/config/database.yml")
      if !available_env[env_name] && (env_name.present? || available_env.size != 1)
        raise "[env] is required where env in [#{available_env.keys.join('|')}], not #{env_name.inspect}"
      end
      available_env[env_name] || available_env.values.first
    end
  
    def file_name()
      identifier = '' 
      if @identifier.present?
        identifier = "-#{@identifier}"
      end
      file_name = "#{@database}#{identifier}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.backup"
      unless @database.start_with?(@app_name)
        file_name.insert(0, "#{@app_name}-")
      end
      file_name
    end
  
    def exe_path(exe_name)
      binding.pry
      pg_path = @bin_dir || self.which(exe_name)
      if pg_path.nil?
        if Gem.win_platform?
          pg_path     = self.which(exe_name, Dir["#{ENV['ProgramFiles']}/PostgreSQL/*/bin/"].join(File::PATH_SEPARATOR))
          pg_path_x86 = self.which(exe_name, Dir["#{ENV['ProgramFiles(x86)']}/PostgreSQL/*/bin/"].join(File::PATH_SEPARATOR)) if ENV['ProgramFiles(x86)'].present?

          if pg_path.present? && pg_path_x86.present?
            raise "More than one executable found when looking for #{exe_name}, specify witch use in config/backups.rb in bin_dir variable:\n  - #{pg_path}\n  - #{pg_path_x86}"
          end
          pg_path = pg_path.nil? ? pg_path_x86 : pg_path
        end
      end
      if pg_path.nil?
        raise "Can find executable #{exe_name}"
      end
      pg_path = File.join(@bin_dir, exe_name) if @bin_dir.present?
      pg_path.gsub("\\", "/") # Running the command with git bash can fail otherwise.
    end
  
    def exclude_table()
      return '' if @excluded_tables.blank?
      exclude_table.map{|table| "-T #{table}"}.join(" ")
    end
  
    def backup_file()
      file = File.join(@backup_dir, self.file_name)
      file.gsub("\\", "/")  # Running the command with git bash can fail otherwise.
    end
  
    def backup_cmd()
      %("#{self.exe_path("pg_dump")}" -i -h #{@host} -p #{@port} -U #{@username} -F c -b -a -v #{self.exclude_table} -f #{self.backup_file} #{@database})
    end
  
    def restore_cmd(backup_file)
      %("#{self.exe_path("pg_restore")}" -i -h #{@host} -p #{@port} -U #{@username} -d #{@database} -v "#{backup_file}")
    end
  
    def backup()
      cmd = self.backup_cmd
  
      puts "", "", "Running command : ", cmd, ""
      if !system({"PGPASSWORD" => @password}, cmd)
        raise "Database backup failed because the system command for pg_dump failed: #{cmd}"
      end
  
      puts "Completed backup to #{backup_file}"
    end
  
    def restore(backup_file)
      raise "Needs to receive backup_file as first argument." if backup_file.blank?
  
      backup_file.gsub!("\\", "/") # Running the command with git bash can fail otherwise.
      cmd = self.restore_cmd(backup_file)
  
      puts "", "", "Running command : ", cmd, ""
      if !system({"PGPASSWORD" => @password}, cmd)
        raise "Database restore failed because the system command for pg_restore failed: \n#{cmd}"
      end
    end
  
    def all_backups(backup_dir)
      all_backups_files = Dir.entries(backup_dir)
      backups = []
      all_backups_files.each do |filename|
        ext = File.extname(filename)
        next if ext != '.backup'
        filename_without_ext = File.basename(filename, ".*" )
        split = filename_without_ext.split('-')
        next if split[0] != @database && !(split[0] == @app_name && split[1] == @database)
        date_str = split[-2] + split[-1]
        date = Date.strptime(date_str, '%Y%m%d%H%M%S')
        backups.push({filename: filename, date: date})
      end
  
      backups.sort_by {|b| b[:date]}
      backups
    end
  
    def date_pattern(date)
      case date
      when :week
        return "%Y%W"
      when :month
        return "%Y%m"
      when :year
        return "%Y"
      else
        raise 'Invalid value for keep_one_backup_each, must be 1.week, 1.month or 1.year'
      end
    end
  
    def delete_old_backup()
      backups = self.all_backups(@backup_dir)
      already_backup = []
      date_pattern = self.date_pattern(@keep_one_backup_each)
  
      backups.each do |b|
        next if b[:date] > Date.today - @keep_all_backup_last
        date = b[:date].strftime(date_pattern)
        if already_backup.include?(date)
          puts "Delete #{b[:filename]}"
          File.delete(File.join(@backup_dir, b[:filename]))
          next
        end
        already_backup.push(date)
      end
    end


    # Cross-platform way of finding an executable in the $PATH.
    #
    #   which('ruby') #=> /usr/bin/ruby
    def which(cmd, paths = ENV['PATH'])
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      paths.split(File::PATH_SEPARATOR).each do |path|
        exts.each { |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable? exe
        }
      end
      return nil
    end
  end
end
