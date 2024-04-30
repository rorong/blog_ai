class BlogController < ApplicationController
  before_action :set_auth_token
  skip_before_action :verify_authenticity_token

  def create
    fetch_tasks
  end
  
  private
  
  def fetch_tasks
    begin
      tasks_response = fetch_tasks_from_api
      if tasks_response.success?
        @tasks = filter_tasks(tasks_response)
        CreateBlogsJob.perform_async(@tasks,@auth_token)
      else
        render_error("An error occurred while fetching tasks: #{tasks_response.code}") && return
      end
    rescue StandardError => e
      render_error("An error occurred while fetching tasks: #{e.message}") && return
    end
    render json: { message: "Blog creation process initiated" }, status: :accepted
  end

  def fetch_tasks_from_api
    base_url = Rails.application.config.api_base_url
    url ="#{base_url}/api/v1/copilot_tasks"
    options = {
      headers: { "Authorization" => @auth_token }
    }
    HTTParty.get(url, options)
  end
  
  def filter_tasks(tasks_response)
    tasks = tasks_response["tasks"]
    tasks.select { |task| task["status"] != "validated" && task["status"] != "completed" && task["status"] != "deleted" }
  end

  def set_auth_token
    @auth_token = request.headers['Authorization']
    render_error('Authorization token is missing', :unauthorized) if @auth_token.nil?
  end
  
  def render_error(message, status = :internal_server_error)
    render json: { error: message }, status: status
  end
  
  
end
