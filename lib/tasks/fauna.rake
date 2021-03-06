
task :environment

namespace :fauna do
  desc 'Migrate your Fauna database to the latest version of your schema'
  task :migrate => :environment do
    puts "Migrating #{Rails.env} Fauna database schema"
    Fauna::Client.context(Fauna.connection) do
      Fauna.migrate_schema!
    end
  end

  desc 'Completely reset your Fauna database'
  task :reset => :environment do
    if Rails.env.production?
      puts "Won't reset #{Rails.env} Fauna database"
    else
      Fauna::Client.context(Fauna.root_connection) do
        puts "Resetting #{Rails.env} Fauna database"
        Fauna::Client.delete('everything')
      end
      Fauna.auth!
    end
  end

  desc "Dump the contents of your Fauna database to 'test/fixtures/fauna'"
  task :dump => :environment do
    puts "Dumping #{Rails.env} Fauna database contents to #{Fauna::FIXTURES_DIR}"
    Fauna::Client.context(Fauna.connection) do
      FileUtils.mkdir_p(Fauna::FIXTURES_DIR)

      class_configs = Fauna.connection.get('/classes')['references'] || {}
      class_configs['users'] = nil

      Dir.chdir(Fauna::FIXTURES_DIR) do
        class_configs.each do |ref, value|
          class_name = ref[0..-8]
          FileUtils.mkdir_p(class_name)

          Dir.chdir(class_name) do
            # FIXME: shouldn't round trip JSON
            File.open('config.json', 'w') { |f| f.write(value.to_json) } if value
            (Fauna.connection.get(class_name)['references'] || {}).each do |inner_ref, inner_value|
              File.open("#{inner_ref.split('/').last}.json", 'w') { |f| f.write(inner_value.to_json) }
            end
          end
        end
      end
    end
  end

  desc 'Load the contents of your Fauna database'
  task :load => :environment do
    puts "Loading #{Rails.env} Fauna database contents from #{Fauna::FIXTURES_DIR}"
    Fauna::Client.context(Fauna.connection) do
      Dir.chdir(Fauna::FIXTURES_DIR) do
        Dir['**/*.json'].collect do |filename|
          value = JSON.parse(File.open(filename) { |f| f.read })
          begin
            Fauna.connection.put(value['ref'], value)
          rescue Fauna::Connection::NotFound
            Fauna.connection.post(value['ref'].split('/')[0..-2].join('/'), value)
          end
        end
      end
    end
  end

end

task :test => ['fauna:reset', 'fauna:migrate', 'fauna:load']
