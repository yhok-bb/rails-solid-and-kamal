class DebugController < ApplicationController
  def headers
    render json: request.headers.env.select { |k, _| k.start_with?('HTTP_') }
  end

  def session_check
    session[:visit_count] = (session[:visit_count] || 0) + 1
    render plain: "server: #{Socket.gethostname}\nvisit_count: #{session[:visit_count]}\n"
  end
end
