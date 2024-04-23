class CreateBlogsJob
  include Sidekiq::Job

  BATCH_SIZE = 10 # Adjust batch size as needed

  def perform(tasks,auth_token)
    @auth_token = auth_token
    tasks.each_slice(BATCH_SIZE) do |batch_tasks|
      batch_prompts = batch_tasks.map { |task| generate_prompt(task["description"]) }
      generated_contents = generate_blog_posts(batch_prompts)
      save_blog_posts(batch_tasks, generated_contents)
      update_task_statuses(batch_tasks)
    end
  end

  private

  def generate_prompt(description)
    prompt_template = "Write a blog post discussing the topic of '{task}'. Explore its significance in the context of your audience's interests and concerns. Consider providing practical examples, insights, and actionable advice to engage readers and add value to their understanding. Aim to deliver a compelling narrative that captivates the audience's attention and encourages further exploration of the subject matter."
    Langchain::Prompt::PromptTemplate.new(template: prompt_template, input_variables: ["task"]).format(task: description)
  end

  def generate_blog_posts(prompts)
    llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_ACCESS_TOKEN"])
    prompts.map { |prompt| llm.chat(messages: [{ role: "user", content: prompt }]).completion }
  end

  def save_blog_posts(tasks, generated_contents)
    tasks.each_with_index do |task, index|
      begin
        folder_name = "task_blogs"
        Dir.mkdir(folder_name) unless Dir.exist?(folder_name)
        File.open("#{folder_name}/blog_#{task["id"]}.txt", "w") do |file|
          file.write(generated_contents[index])
        end
      rescue StandardError => e
        Rails.logger.error("Error saving blog post for task #{task["id"]}: #{e.message}")
      end
    end
  end
  
  def update_task_statuses(tasks)
    tasks.each do |task|
      begin
        url = Rails.env.production? ? "https://cc.heymira.ai/api/v1/tasks/#{task['id']}" : "http://localhost:3000/api/v1/tasks/#{task['id']}"
        params = {
          project_id: task["project_id"],
          organization_id: task["organization_id"],
          task: {
            status: "completed"
          }
        }
        options = { headers: { "Authorization" => @auth_token }, body: params }
        HTTParty.patch(url, options)
      rescue StandardError => e
        Rails.logger.error("Error updating task status for task #{task['id']}: #{e.message}")
      end
    end
  end
end
