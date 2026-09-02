#!/usr/bin/env sh
set -eu

workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

minikube image build -t platform/auth:dev "$workspace_dir/auth-service"
minikube image build -t platform/network:dev "$workspace_dir/network-service"
minikube image build -t platform/aws:dev "$workspace_dir/aws-service"
minikube image build -t platform/frontend:dev "$workspace_dir/frontend-service"

