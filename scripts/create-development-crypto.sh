#!/usr/bin/env sh
set -eu

namespace=${1:-operations-platform}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$work_dir/jwt-private.pem"
openssl rsa -pubout -in "$work_dir/jwt-private.pem" -out "$work_dir/jwt-public.pem"

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$namespace" create secret generic platform-auth-crypto \
  --from-file=jwt-private.pem="$work_dir/jwt-private.pem" \
  --from-file=jwt-public.pem="$work_dir/jwt-public.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created development JWT keys in Kubernetes secret platform-auth-crypto."
echo "Add SAML SP keys and Entra metadata to that secret before enabling SAML."

