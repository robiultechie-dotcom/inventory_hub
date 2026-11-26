# frozen_string_literal: true

require "test_helper"
require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

module CapybaraChromeCdpFix
  def execute_cdp(cmd, params = nil, **kwargs)
    merged = (params || {}).merge(kwargs)
    if cmd == "Storage.clearDataForOrigin" && merged[:origin] == "*"
      uri = URI.parse(browser.current_url)
      return unless uri.scheme&.start_with?("http")

      origin = "#{uri.scheme}://#{uri.host}"
      origin = "#{origin}:#{uri.port}" if uri.port
      merged = merged.merge(origin: origin)
    end

    super(cmd, **merged)
  rescue URI::InvalidURIError
    nil
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(CapybaraChromeCdpFix)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_options|
    driver_options.add_argument("--no-sandbox")
    driver_options.add_argument("--disable-dev-shm-usage")
  end
end
