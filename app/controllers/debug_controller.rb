class DebugController < ApplicationController
  def headers
    render json: request.headers.env.select { |k, _| k.start_with?('HTTP_') }
  end
end
