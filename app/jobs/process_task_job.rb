class ProcessTaskJob < ApplicationJob

  def perform(task_id)
    sleep(5)
    logger.info("Task #{task_id} processed")
  end
end
