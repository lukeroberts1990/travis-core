module Travis
  module Github
    module Services
      class SyncUser < Travis::Services::Base
        class Repository
          class << self
            def unpermit_all(user, repositories)
              user.permissions.where(:repository_id => repositories.map(&:id)).delete_all unless repositories.empty?
            end
          end

          attr_reader :user, :data, :repo, :hooks

          def initialize(user, data, hooks)
            @user = user
            @data = data
            @hooks = hooks
          end

          def run
            @repo = find || create
            update
            if permission
              sync_permissions
            elsif permit?
              permit
            end
            repo
          end

          private

            def find
              ::Repository.where(:github_id => github_id).first
            end

            def create
              ::Repository.create!(:owner_name => owner_name, :name => name, github_id: github_id)
            end
            # instrument :create, :level => :debug

            def permission
              @permission ||= user.permissions.where(:repository_id => repo.id).first
            end

            def sync_permissions
              if permit?
                permission.update_attributes!(permission_data)
              else
                permission.destroy
              end
            end

            def permit?
              push_access? || admin_access? || repo.private?
            end

            def permit
              user.permissions.create!({
                :user  => user,
                :repository => repo
              }.merge(permission_data))
            end
            # instrument :permit, :level => :debug

            def update
              repo.update_attributes!({
                github_id: data['id'],
                private: data['private'],
                description: data['description'],
                url: data['homepage'],
                default_branch: data['default_branch'],
                github_language: data['language'],
                name: name,
                owner_name: owner_name,
                active: hook_active?
              })
            rescue ActiveRecord::RecordInvalid
              # ignore for now. this seems to happen when multiple syncs (i.e. user sign
              # in requests are running in parallel?
            rescue GH::Error(response_status: 404) => e
              Travis.logger.warn "[github][services][user_sync] GitHub info was not available for #{repo.owner_name}/#{repo.name}: #{e.inspect}"
            end

            def owner_name
              data['owner']['login']
            end

            def name
              data['name']
            end

            def github_id
              data['id']
            end

            def permission_data
              data['permissions']
            end

            def push_access?
              permission_data['push']
            end

            def admin_access?
              permission_data['admin']
            end

            def hook_active?
              hooks
                .select { |hook| hook['name'] == 'travis' && hook['domain'] == hook_domain }
                .any?   { |hook| hook['active'] }
            end

            def hook_domain
              Travis.config.service_hook_url || ''
            end
        end
      end
    end
  end
end
