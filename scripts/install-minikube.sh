#!/usr/bin/env sh
set -eu

namespace=${PLATFORM_NAMESPACE:-operations-platform}

minikube status >/dev/null 2>&1 || minikube start --driver=docker
minikube addons enable ingress
"$(dirname "$0")/create-development-crypto.sh" "$namespace"
"$(dirname "$0")/build-images.sh"
helm upgrade --install operations-platform "$(dirname "$0")/../helm/platform" --namespace "$namespace" --create-namespace

echo "Map $(minikube ip) platform.local in /etc/hosts, then open http://platform.local"

