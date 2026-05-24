#!/bin/bash

COUNT=${1:-5}

for i in $(seq 1 $COUNT); do
  ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)
  docker compose exec -T web bin/rails runner \
    "task = Task.create!(title: 'Task-${ID}', body: 'Auto-generated ${ID}'); ProcessTaskJob.perform_later(task.id); puts \"Created Task \#{task.id}: Task-${ID}\""
done
