# Set the following in your deploy.rb:
set :database_name,      "" # db name
set :database_username,  "" # db username
set :database_host,      "" # database hostname
set :database_password,  "" # database password, as defined in database.yml
set :ssh_server,         "" # name of the server in your .ssh/config

Capistrano::Configuration.instance(:must_exist).load do
  
  namespace :db do

    set :dump_root_path, "/tmp"
    set :now, Time.now
    set :formatted_time, now.strftime("%Y-%m-%d")
    set :dump_path, "#{dump_root_path}/#{database_name}_dump_#{formatted_time}.sql"
    set :keep_dumps, 3

    def give_description(desc_string)
      puts "  ** #{desc_string}"
    end

    desc "Remove all but the last 3 production dumps"
    task :cleanup, :roles => :app, :except => { :no_release => true } do
      cmd = "ls #{dump_root_path}/*"

      give_description "Cleaning up files"
      
      run cmd do |channel, stream, data|
        unless stream == :err
          each_database_file_with_index(data) do |file_name, index|
            if index >= keep_dumps
              give_description "Removing old dump #{file_name}"
              run "rm -rf #{file_name}"
            end
          end
        end
      end
    end
    
    def each_database_file_with_index(data)
      all_files = data.split(" ")
      
      if all_files
        if database_files = all_files.select { |f| f =~ /#{database_name}/ }
          database_files.sort.reverse.each_with_index do |file, index|
            yield file, index
          end
        end
      end
    end

    task :create_dump, :roles => :app, :except => { :no_release => true } do
      command = <<-HERE
      mysqldump -u #{database_username} -h #{database_host} -p#{database_password} -Q  --add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction --ignore-table=#{database_name}.sessions #{database_name} > #{dump_path}
    HERE

      give_description "About to dump production DB"

      run command
      session_schema_dump
    end
    
    task :session_schema_dump, :roles => :app, :except => { :no_release => true } do
      command = <<-HERE
      mysqldump -u #{database_username} -h #{database_host} -p#{database_password} -Q --add-drop-table --single-transaction --no-data #{database_name} sessions >> #{dump_path}
    HERE

      give_description "Dumping sessions table from db"

      run command
    end

    desc "Create a dump of the production database"
    task :dump, :roles => :app, :except => { :no_release => true } do
      cleanup
      create_dump

      cmd = "gzip -9 #{dump_path}"

      give_description "Gzip'ing the file"
      run cmd
    end
    
    task :before_dump do
      give_description "Removing old production dump from today"
      run "rm -rf #{dump_path}.gz"
    end

    desc "Make a production dump, transfer it to this machine"
    task :dump_and_transfer, :roles => :app, :except => { :no_release => true } do
      dump
      transfer
    end
    
    task :transfer, :roles => :app, :except => { :no_release => true } do
      cmd = "scp #{ssh_server}:#{dump_path}.gz ."

      give_description "Grabbing the dump"
      give_description "executing locally: #{cmd}"
      
      `#{cmd}`
    end
  end
  
end