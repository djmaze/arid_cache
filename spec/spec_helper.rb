ENV["RAILS_ENV"] ||= 'test'
root_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))
$LOAD_PATH.unshift(File.join(root_path, '/test/lib')) # make requiring from test/lib easy


require 'bundler/setup'
Bundler.require

RAILS_DEFAULT_LOGGER = ENV["STDOUT"] ? Logger.new(STDOUT) : Logger.new(File.join(root_path, '/test/log/test.log'))
RAILS_CACHE = ActiveSupport::Cache.lookup_store(:file_store, File.join(root_path, '/tmp/cache'))

#load(File.join(root_path, sitemap_rails, 'Rakefile'))
require File.join(root_path, 'spec', 'rails-2.3.8', 'config', 'boot')
Rails.boot!

require 'fix_active_support_file_store_expires_in'

# Set loggers for all frameworks
require 'active_record'
require 'action_controller'
for framework in ([ :active_record, :action_controller, :action_mailer ])
  if Object.const_defined?(framework.to_s.camelize)
    framework.to_s.camelize.constantize.const_get("Base").logger = Rails.logger
  end
end
ActiveSupport::Dependencies.logger = Rails.logger
Rails.cache.logger = Rails.logger
debugger
require 'db_prepare' #File.join(root_path, 'spec', 'rails-config', 'schema')

#require 'spec/autorun'

#require 'action_controller'
#require 'active_support/test_case'
#require 'active_record/fixtures' if defined?(ActiveRecord::Base)
#require 'spec/test/unit'
# require 'spec/rails/extensions/spec/runner/configuration'
# require 'spec/rails/extensions/active_support/test_case'
# require 'spec/rails/extensions/active_record/base'
#ActiveSupport::TestCase.use_transactional_fixtures = true
#Spec::Example::ExampleGroupFactory.default(ActiveSupport::TestCase)

#require 'spec/rails'

# require 'rack/utils'
#
# require 'action_controller/test_process'
# require 'action_controller/integration'
# require 'active_support/test_case'
# require 'active_record/fixtures' if defined?(ActiveRecord::Base)
# require 'spec/test/unit'
# require 'spec/rails/matchers'
# require 'spec/rails/mocks'
# require 'spec/rails/example'
# require 'spec/rails/extensions'
# require 'spec/rails/interop/testcase'
#
# Spec::Example::ExampleGroupFactory.default(ActiveSupport::TestCase)
#
# if ActionView::Base.respond_to?(:cache_template_extensions)
#   ActionView::Base.cache_template_extensions = false
# end


# require 'spec/autorun'
#require 'mock_rails'
require 'blueprint'
AridCache.init_rails

Dir[File.expand_path(File.join(File.dirname(__FILE__),'support','**','*.rb'))].each {|f| require f}

Spec::Runner.configure do |config|
  include ActiveRecordQueryMatchers
  config.mock_with :mocha
  #config.use_transactional_fixtures = true
  config.before(:all) do
    Sham.reset(:before_all)
  end

  config.before(:each) do
    Sham.reset(:before_each)
    full_example_description = "#{self.class.description} #{@method_name}"
    RAILS_DEFAULT_LOGGER.info("\n\n#{full_example_description}\n#{'-' * (full_example_description.length)}")
  end
end