#!/bin/bash

echo "Testing SpacetimeDB OAuth endpoints..."
echo ""

echo "1. Testing OIDC Discovery endpoint:"
curl -s https://auth.spacetimedb.com/oidc/.well-known/openid-configuration | jq . 2>/dev/null || echo "Discovery endpoint failed"

echo ""
echo "2. Testing Authorization endpoint:"
curl -I https://auth.spacetimedb.com/oidc/authorize 2>/dev/null | head -1

echo ""
echo "3. Testing Token endpoint:"
curl -I https://auth.spacetimedb.com/oidc/token 2>/dev/null | head -1

echo ""
echo "4. Your OAuth URL:"
echo "https://auth.spacetimedb.com/oidc/authorize?client_id=client_031CSnBZhPFgz5oj5Alo0a&redirect_uri=http://127.0.0.1:31419&response_type=code&scope=openid%20profile%20email&code_challenge=test&code_challenge_method=S256"
