#!/usr/bin/env sh
set -eu

url=$(azd env get-value DEMO_URL)
echo "Demo UI: $url"
echo "Sign in with the configured demo-owner Microsoft account."
