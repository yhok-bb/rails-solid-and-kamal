class ApplicationController < ActionController::Base
  include Authentication
  before_action { response.set_header("X-Served-By", Socket.gethostname) }
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
