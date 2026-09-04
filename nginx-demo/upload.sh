#!/usr/bin/env bash

export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
REPO=europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse

# backend
BSHA=$(cd ~/eri-proj/fullstacktodo/backend-project && git rev-parse --short HEAD)
docker tag  todo-backend:local  $REPO/backend:$BSHA
docker push $REPO/backend:$BSHA
echo "pushed backend:$BSHA"

# frontend
FSHA=$(cd ~/eri-proj/fullstacktodo/frontend-project && git rev-parse --short HEAD)
docker tag  todo-frontend:local $REPO/frontend:$FSHA
docker push $REPO/frontend:$FSHA
echo "pushed frontend:$FSHA"
