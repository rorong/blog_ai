class Api::V1::BlogController < ApplicationController
  skip_before_action :verify_authenticity_token
  def create
    description = params[:description]
    prompt_template = "Write a blog post discussing the topic of '{task}'. Explore its significance in the context of your audience's interests and concerns. Consider providing practical examples, insights, and actionable advice to engage readers and add value to their understanding. Aim to deliver a compelling narrative that captivates the audience's attention and encourages further exploration of the subject matter."

    prompt = Langchain::Prompt::PromptTemplate.new(template: prompt_template, input_variables: ["task"])
    prompt = prompt.format(task: description)  
    begin  
      llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_ACCESS_TOKEN"])
      generated_content = llm.chat(messages: [{role: "user", content: prompt}]).completion
      render json: { blog_content: generated_content }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error generating blog post: #{e.message}")
      render json: { error: "Failed to generate blog post" }, status: :internal_server_error
    end
  end
end
