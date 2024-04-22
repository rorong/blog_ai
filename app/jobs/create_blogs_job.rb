class CreateBlogsJob
  include Sidekiq::Job

  BATCH_SIZE = 10 # Adjust batch size as needed

  def perform(tasks)
    tasks.each_slice(BATCH_SIZE) do |batch_tasks|
      batch_prompts = batch_tasks.map { |task| generate_prompt(task["description"]) }
      generated_contents = generate_blog_posts(batch_prompts)
      save_blog_posts(batch_tasks, generated_contents)
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
        File.open("blog_#{task["id"]}.txt", "w") do |file|
          file.write(generated_contents[index])
        end
      rescue StandardError => e
        Rails.logger.error("Error saving blog post for task #{task["id"]}: #{e.message}")
      end
    end
  end
  
end
