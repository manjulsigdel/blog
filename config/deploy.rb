# config valid for current version and patch releases of Capistrano
lock "~> 3.11.0"

set :application, "blog"
set :repo_url, "git@github.com:manjulsigdel/blog.git"
set :user, "prospero"

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp
set :branch, "master"

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, "/var/www/my_app_name"

# Multistage Deployment #
#####################################################################################
set :stages,              %w(dev staging prod)
set :default_stage,       "staging"

# Other Options #
#####################################################################################
set :ssh_options,         { :forward_agent => true }
set :default_run_options, { :pty => true }

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# append :linked_files, "config/database.yml"

# Default value for linked_dirs is []
# append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

# Set current time #
#######################################################################################
require 'date'
set :current_time, DateTime.now
set :current_timestamp, DateTime.now.to_time.to_i

namespace :setup do
    desc "Create shared folders"
    task :create_storage_folder do
        on roles(:all) do
            execute "mkdir -p #{shared_path}/storage"
            execute "mkdir -p #{shared_path}/storage/app"
            execute "mkdir -p #{shared_path}/storage/framework"
            execute "mkdir -p #{shared_path}/storage/framework/cache"
            execute "mkdir -p #{shared_path}/storage/framework/sessions"
            execute "mkdir -p #{shared_path}/storage/framework/views"
            execute "mkdir -p #{shared_path}/storage/logs"
        end
    end

    desc "Create overlay folders"
    task :create_overlay_folder do
        on roles(:all) do
            execute "mkdir -p #{fetch(:overlay_path)}"
        end
    end

    desc "Set up project"
    task :init do
        on roles(:all) do
            invoke "setup:create_storage_folder"
            invoke "setup:create_overlay_folder"
            invoke "devops:copy_parameters"
        end
    end
end

# DevOps Tasks #
#######################################################################################
namespace :devops do
    desc "Run Laravel Artisan migrate task."
    task :migrate do
        on roles(:app) do
            within release_path do
                execute :php, "artisan migrate --force"
            end
        end
    end

    desc "Run Laravel Artisan migrate:fresh task."
    task :migrate_fresh do
        on roles(:app) do
            within release_path do
                execute :php, "artisan migrate:fresh --force"
            end
        end
    end

    desc "Run Laravel Artisan seed task."
    task :seed do
        on roles(:app) do
            within release_path do
            execute :php, "artisan db:seed --force"
            end
        end
    end

    desc "Optimize Laravel Class Loader"
    task :optimize do
        on roles(:app) do
            within release_path do
                execute :php, "artisan clear-compiled"
                execute :php, "artisan optimize"
            end
        end
    end

    desc 'Reload nginx server'
    task :nginx_reload do
        on roles(:all) do
            execute :sudo, :service, "nginx reload"
        end
    end

    desc 'Restart php-fpm'
    task :php_restart do
        on roles(:all) do
            execute :sudo, :service, "php7.2-fpm restart"
        end
    end

    desc "Copy Parameter File(s)"
    task :copy_parameters do
        on roles(:all) do |host|
            %w[ parameters.sed ].each do |f|
                upload! "./config/deploy/parameters/#{fetch(:env)}/" + f , "#{fetch(:overlay_path)}/" + f
            end
        end
    end
end


# Installation Tasks #
#######################################################################################
namespace :installation do
    desc 'Copy vendor directory from last release'
    task :vendor_copy do
        on roles(:web) do
            puts ("--> Copy vendor folder from previous release")
            execute "vendorDir=#{current_path}/vendor; if [ -d $vendorDir ] || [ -h $vendorDir ]; then cp -a $vendorDir #{release_path}/vendor; fi;"
        end
    end

    desc "Running Composer Install"
    task :composer_install do
        on roles(:app) do
            within release_path do
                execute :composer, "install --quiet"
                execute :composer, "dump-autoload -o"
            end
        end
    end

    desc "Running npm Install"
    task :npm_install do
        on roles(:app) do
            within release_path do
                execute :npm, "install"
                execute :npm, "run prod"
            end
        end
    end

    desc "Set environment variables"
    task :set_env_variables do
        on roles(:app) do
              puts ("--> Copying environment configuration file")
              execute "cp #{release_path}/.env.server #{release_path}/.env"
              puts ("--> Setting environment variables")
              execute "sed --in-place -f #{fetch(:overlay_path)}/parameters.sed #{release_path}/.env"
        end
    end

    desc "Symbolic link for shared folders"
    task :create_symlink do
        on roles(:app) do
            within release_path do
                execute "rm -rf #{release_path}/storage"
                execute "rm -rf #{release_path}/public/uploads"
                execute "ln -s #{shared_path}/storage/ #{release_path}"
                execute "ln -s #{shared_path}/uploads/ #{release_path}/public"
            end
        end
    end

    desc "User permission to web group"
    task :user_permission do
        on roles(:all) do
            puts("--> Setting permission to laravel bootstrap/cache and storage directory")
            execute "chgrp -R www-data #{current_path}/storage #{current_path}/bootstrap/cache"
        end
    end

    desc "Create ver.txt"
    task :create_ver_txt do
        on roles(:all) do
            puts ("--> Copying ver.txt file")
            execute "cp #{release_path}/config/deploy/ver.txt.example #{release_path}/public/ver.txt"
            execute "sed --in-place 's/%date%/#{fetch(:current_time)}/g
                        s/%branch%/#{fetch(:branch)}/g
                        s/%revision%/#{fetch(:current_revision)}/g
                        s/%deployed_by%/#{fetch(:user)}/g' #{release_path}/public/ver.txt"
            execute "find #{release_path}/public -type f -name 'ver.txt' -exec chmod 664 {} \\;"
        end
    end

    desc "Generate Swagger API Docs"
    task :create_api_docs do
        on roles(:app) do
            within release_path do
                execute :php, "artisan l5-swagger:generate"
            end
        end
    end
end


# Tasks Execution #
#######################################################################################
#desc "Deploy Application"
#namespace :deploy do
#    after :updated, "installation:vendor_copy"
#    after :updated, "installation:composer_install"
#    after :updated, "installation:set_env_variables"
#    after :published, "installation:create_symlink"
#    after :finished, "installation:create_ver_txt"
#    after :finished, "installation:create_api_docs"
#    after :finished, "devops:migrate"
#end

#after "deploy", "devops:nginx_reload"
#after "deploy", "devops:php_restart"
