class CreateBlogsJob
  include Sidekiq::Job

  BATCH_SIZE = 10 # Adjust batch size as needed

  def perform(tasks,auth_token)
    @auth_token = auth_token
    tasks.each_slice(BATCH_SIZE) do |batch_tasks|
      batch_prompts = batch_tasks.map { |task| generate_prompt(task["description"]) }
      generated_contents = generate_blog_posts(batch_prompts)
      save_blog_posts(batch_tasks, generated_contents)
      update_task_statuses(batch_tasks,"completed")
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
        filename = "#{folder_name}/blog_#{task["id"]}.txt"
        File.open(filename, "w") do |file|
          file.write(generated_contents[index])
        end
        check_blog_validity(generated_contents,task)
      rescue StandardError => e
        Rails.logger.error("Error saving blog post for task #{task["id"]}: #{e.message}")
      end
    end
  end
  
  def check_blog_validity(blog,task)
    prompt_template = <<-PROMPT
    "Evaluate the following blog post for validity:
    
    Topic: '{topic}'
    
    Criteria for determining validity:
    1. Relevance: Assess whether the content is relevant to the intended audience and aligns with the blog's theme.
    2. Accuracy: Verify the factual correctness of the information presented in the blog post.
    3. Engagement: Evaluate the readability and engagement level of the content to ensure it captivates and retains the audience's interest.
    4. Originality: Determine if the blog offers unique insights or perspectives on the topic, avoiding plagiarism and regurgitated content.
    5. Ethical Considerations: Consider the ethical implications of the content, ensuring it adheres to industry standards and promotes responsible discourse.

    After reviewing the blog post, provide feedback on its overall validity, highlighting areas of strength and areas for improvement.
    
    Blog Post:
    {blog}"
  PROMPT
  prompt = Langchain::Prompt::PromptTemplate.new(template: prompt_template, input_variables: ["topic", "blog"]).format(topic: task[:description], blog: blog)
    llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_ACCESS_TOKEN"])
    response = llm.chat(messages: [{ role: "user", content: prompt }]).completion
    
    #logic for validaity here
    update_task_statuses(tasks,"validated")
  end
  
  def update_task_statuses(tasks,status)
    tasks.each do |task|
      begin
        url = Rails.env.production? ? "https://cc.heymira.ai/api/v1/tasks/#{task['id']}" : "http://localhost:3000/api/v1/tasks/#{task['id']}"
        params = {
          project_id: task["project_id"],
          organization_id: task["organization_id"],
          task: {
            status: status
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
