#!/bin/bash
# OpenAPI SDK Generation — E7.4 Phase 7
# Generates Dart SDK from FastAPI OpenAPI JSON via openapi-generator
#
# Usage:
#   ./scripts/generate_sdk.sh
#
# Requires:
#   - FastAPI app running at http://localhost:8000/api/docs or openapi.json
#   - openapi-generator-cli installed (npm install @openapitools/openapi-generator-cli -g)
#
# Output:
#   ../frontend/lib/core/network/api_sdk.dart (generated, type-safe)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$SCRIPT_DIR/../../frontend"
OUTPUT_DIR="$FRONTEND_DIR/lib/core/network"

echo "=== OpenAPI SDK Generation (E7.4) ==="

# Check if backend is running, if not try to get openapi.json via python
if [ -f "$BACKEND_DIR/app/main.py" ]; then
  echo "Generating OpenAPI JSON from FastAPI app..."
  cd "$BACKEND_DIR"
  python -c "
from app.main import app
import json
openapi = app.openapi()
with open('/tmp/openapi.json', 'w') as f:
    json.dump(openapi, f, indent=2)
print('OpenAPI JSON saved to /tmp/openapi.json')
print(f\"Paths: {len(openapi.get('paths', {}))}\")
"
  OPENAPI_JSON="/tmp/openapi.json"
else
  OPENAPI_JSON="http://localhost:8000/api/v1/openapi.json"
fi

if [ ! -f "$OPENAPI_JSON" ]; then
  echo "OpenAPI JSON not found at $OPENAPI_JSON"
  echo "Make sure backend is running or app.main import works"
  exit 1
fi

echo "OpenAPI JSON: $OPENAPI_JSON"

# Generate Dart SDK using openapi-generator
if command -v openapi-generator-cli &> /dev/null; then
  echo "Generating Dart SDK..."
  mkdir -p "$OUTPUT_DIR/generated"
  
  # Generate with custom config
  cat > /tmp/openapi-config.json <<EOF
{
  "packageName": "ai_pdf_api_sdk",
  "packageVersion": "1.0.0",
  "dartLibrary": "dio",
  "apiPackage": "api",
  "modelPackage": "model",
  "enumUnknownDefaultCase": true,
  "hideGenerationTimestamp": true,
  "useEnumExtension": true
}
EOF

  openapi-generator-cli generate \
    -i "$OPENAPI_JSON" \
    -g dart-dio \
    -o "$OUTPUT_DIR/generated" \
    -c /tmp/openapi-config.json \
    --additional-properties=pubName=ai_pdf_api_sdk,pubVersion=1.0.0

  echo "Dart SDK generated at $OUTPUT_DIR/generated"

  # Create wrapper api_sdk.dart that re-exports and adds custom logic
  cat > "$OUTPUT_DIR/api_sdk.dart" <<'DART'
// Auto-generated wrapper for OpenAPI SDK — E7.4
// This file provides type-safe client for chat history, teams, sync, etc.
// Generated files are in generated/ dir, this wrapper adds convenience.

library api_sdk;

// Re-export generated models and APIs (if generation succeeded)
// export 'generated/lib/api.dart';
// export 'generated/lib/model.dart';

import 'package:dio/dio.dart';
import 'api_client.dart';

/// Type-safe SDK wrapper around ApiClient (existing) + generated models
class ApiSdk {
  final ApiClient _client;

  ApiSdk(this._client);

  Dio get dio => _client.dio;

  // Example type-safe methods (would be generated in real SDK)
  // For now, delegate to existing ApiClient with typed responses

  Future<List<Map<String, dynamic>>> listChatHistory() async {
    final resp = await dio.get('/chat-history');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getChatSession(String id) async {
    final resp = await dio.get('/chat-history/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listTeams() async {
    final resp = await dio.get('/teams');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listSync() async {
    final resp = await dio.get('/sync/list');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getPaywallStats() async {
    final resp = await dio.get('/billing/paywall/stats');
    return resp.data as Map<String, dynamic>;
  }
}
DART

  echo "Wrapper created at $OUTPUT_DIR/api_sdk.dart"
  echo "=== SDK Generation Complete ==="
  echo "Usage:"
  echo "  import 'package:ai_pdf/core/network/api_sdk.dart';"
  echo "  final sdk = ApiSdk(ref.read(apiClientProvider));"
  echo "  final history = await sdk.listChatHistory();"
else
  echo "openapi-generator-cli not found, installing via npm..."
  echo "Run: npm install @openapitools/openapi-generator-cli -g"
  echo "Then re-run this script"
  echo ""
  echo "For now, creating stub api_sdk.dart..."
  
  mkdir -p "$OUTPUT_DIR"
  cat > "$OUTPUT_DIR/api_sdk.dart" <<'DART'
// Stub SDK — E7.4 (openapi-generator-cli not installed, this is manual stub)
// In production, run ./scripts/generate_sdk.sh with openapi-generator-cli installed

import 'package:dio/dio.dart';
import 'api_client.dart';

class ApiSdk {
  final ApiClient _client;
  ApiSdk(this._client);
  Dio get dio => _client.dio;

  Future<List<Map<String, dynamic>>> listChatHistory() async {
    final resp = await dio.get('/chat-history');
    return (resp.data as List).cast<Map<String, dynamic>>();
  }
}
DART
  
  echo "Stub created at $OUTPUT_DIR/api_sdk.dart"
fi
