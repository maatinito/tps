# This file was generated by the `rails generate rspec:install` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# The `.rspec` file contains `--require rails_helper`, which requires spec_helper.rb,
# causing this file to always be loaded, without a need to explicitly require it in any
# files.
#
# Given that it is always loaded, you are encouraged to keep this file as
# light-weight as possible. Requiring heavyweight dependencies from this file
# will add to the boot time of your test suite on EVERY test run, even for an
# individual file that may not need all of that loaded. Instead, consider making
# a separate helper file that requires the additional dependencies and performs
# the additional setup, and require it from the spec files that actually need
# it.
#
# The `.rspec` file also contains a few flags that are not defaults but that
# users commonly want.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration

require 'rspec'
require 'capybara/rspec'
require 'capybara-screenshot/rspec'
require 'capybara/email/rspec'
require 'database_cleaner'
require 'webmock/rspec'
require 'shoulda-matchers'
require 'devise'
require 'factory_bot'
require 'axe/rspec'

require 'selenium/webdriver'
Capybara.javascript_driver      = ENV.fetch('CAPYBARA_DRIVER', 'headless_chrome').to_sym
Capybara.ignore_hidden_elements = false

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, browser: :chrome)
end

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--window-size=1440,900')

  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: ['disable-dev-shm-usage', 'disable-software-rasterizer', 'mute-audio', 'window-size=1440,900'] }
  )

  client = Selenium::WebDriver::Remote::Http::Default.new
  client.read_timeout = 120

  Capybara::Selenium::Driver.new app,
    browser:              :chrome,
    desired_capabilities: capabilities,
    options:              options,
    http_client:          client
end

#---- From https://gist.github.com/danwhitston/5cea26ae0861ce1520695cff3c2c3315#using-capybara-with-a-remote-selenium-server

Capybara.register_driver :wsl do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--window-size=1440,900')

  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: ['disable-dev-shm-usage', 'disable-software-rasterizer', 'mute-audio', 'window-size=1440,900'] }
  )

  Capybara::Selenium::Driver.new(app,
    browser:              :remote,
    url:                  "http://localhost:4444/wd/hub",
    desired_capabilities: capabilities,
    options:              options)
end

# FIXME: remove this line when https://github.com/rspec/rspec-rails/issues/1897 has been fixed
Capybara.server = :puma, { Silent: true }

Capybara.default_max_wait_time = 2

# Save a snapshot of the HTML page when an integration test fails
Capybara::Screenshot.autosave_on_failure = true
# Keep only the screenshots generated from the last failing test suite
Capybara::Screenshot.prune_strategy = :keep_last_run
# Tell Capybara::Screenshot how to take screenshots when using the headless_chrome driver
Capybara::Screenshot.register_driver :headless_chrome do |driver, path|
  driver.browser.save_screenshot(path)
end

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].each { |f| require f }
Dir[Rails.root.join('spec', 'factories', '**', '*.rb')].each { |f| require f }

VCR.configure do |c|
  c.ignore_localhost = true
  c.hook_into :webmock
  c.cassette_library_dir = 'spec/fixtures/cassettes'
  c.configure_rspec_metadata!
  c.ignore_hosts 'test.host', 'chromedriver.storage.googleapis.com'
end

DatabaseCleaner.strategy = :transaction

TPS::Application.load_tasks
Rake.application.options.trace = false

include Warden::Test::Helpers

include SmartListing::Helper
include SmartListing::Helper::ControllerExtensions

module SmartListing
  module Helper
    def view_context
      'mock'
    end
  end
end

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.filter_run_excluding disable: true
  config.color = true
  config.tty = true

  config.run_all_when_everything_filtered = true
  config.filter_run :focus => true

  config.order = 'random'
  # Fix the seed not changing between runs when using Spring
  # See https://github.com/rails/spring/issues/113
  config.seed = srand % 0xFFFF unless ARGV.any? { |arg| arg =~ /seed/ || arg =~ /rand:/ }

  config.include FactoryBot::Syntax::Methods

  config.before(:each) do
    Flipper.enable(:instructeur_bypass_email_login_token)
  end

  config.before(:all) {
    Rake.verbose false

    Warden.test_mode!

    Typhoeus::Expectation.clear

    ActionMailer::Base.deliveries.clear

    ActiveStorage::Current.host = 'http://test.host'

    Geocoder.configure(lookup: :test)
  }

  RSpec::Matchers.define :have_same_attributes_as do |expected, options|
    match do |actual|
      ignored = [:id, :procedure_id, :updated_at, :created_at]
      if options.present? && options[:except]
        ignored = ignored + options[:except]
      end
      actual.attributes.with_indifferent_access.except(*ignored) == expected.attributes.with_indifferent_access.except(*ignored)
    end
  end

  # Asserts that a given select element exists in the page,
  # and that the option(s) with the given value(s) are selected.
  #
  # Usage: expect(page).to have_selected_value('Country', selected: 'Australia')
  #
  # For large lists, this is much faster than `have_select(location, selected: value)`,
  # as it doesn’t check that every other options are not selected.
  RSpec::Matchers.define(:have_selected_value) do |select_locator, options|
    match do |page|
      values = options[:selected].is_a?(String) ? [options[:selected]] : options[:selected]

      select_element = page.first(:select, select_locator)
      select_element && values.all? do |value|
        select_element.first(:option, value).selected?
      end
    end
  end

  def save_timestamped_screenshot(page, meta)
    filename = File.basename(meta[:file_path])
    line_number = meta[:line_number]

    time_now = Time.zone.now
    timestamp = "#{time_now.strftime('%Y-%m-%d-%H-%M-%S.')}#{format('%03d', (time_now.usec / 1000).to_i)}"

    screenshot_name = "screenshot-#{filename}-#{line_number}-#{timestamp}.png"
    screenshot_path = "#{ENV.fetch('CIRCLE_ARTIFACTS', Rails.root.join('tmp', 'capybara'))}/#{screenshot_name}"

    page.save_screenshot(screenshot_path)

    puts "\n  Screenshot: #{screenshot_path}"
  end

  config.after(:each) do |example|
    if example.metadata[:js]
      save_timestamped_screenshot(Capybara.page, example.metadata) if example.exception
    end
  end
end
