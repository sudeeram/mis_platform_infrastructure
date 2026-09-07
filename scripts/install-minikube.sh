#!/usr/bin/env sh
set -eu

namespace=${PLATFORM_NAMESPACE:-operations-platform}
branch=$(git -C "$(dirname "$0")/.." branch --show-current)

if [ "$branch" != "develop" ]; then
  echo "Minikube deployment is permitted only from the develop branch (current: $branch)." >&2
  exit 1
fi

minikube status >/dev/null 2>&1 || minikube start --driver=docker
minikube addons enable ingress
"$(dirname "$0")/create-development-crypto.sh" "$namespace"
"$(dirname "$0")/build-images.sh"
helm upgrade --install operations-platform "$(dirname "$0")/../helm/platform" --namespace "$namespace" --create-namespace

echo "Map $(minikube ip) platform.local in /etc/hosts, then open http://platform.local"
