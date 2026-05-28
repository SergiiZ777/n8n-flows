#!/bin/bash
# n8n → GitHub Full Backup Script
# Run this on your Hetzner server where n8n is hosted
# Usage: N8N_API_KEY=xxx GITHUB_TOKEN=xxx bash backup.sh

set -e

N8N_URL="${N8N_URL:-http://localhost:5678}"
GITHUB_REPO="${GITHUB_REPO:-SergiiZ777/n8n-flows}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

if [ -z "$N8N_API_KEY" ] || [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ Set N8N_API_KEY and GITHUB_TOKEN env vars"
  echo "   N8N_API_KEY: n8n Settings → API → Create key"
  echo "   GITHUB_TOKEN: github.com/settings/tokens → repo scope"
  exit 1
fi

echo "📦 Fetching all workflows from n8n..."

python3 - << PYTHON
import json, sys, base64, urllib.request, urllib.error, os, re

N8N_URL = os.environ.get('N8N_URL', 'http://localhost:5678')
N8N_KEY = os.environ['N8N_API_KEY']
GH_TOKEN = os.environ['GITHUB_TOKEN']
GH_REPO = os.environ.get('GITHUB_REPO', 'SergiiZ777/n8n-flows')
GH_BRANCH = os.environ.get('GITHUB_BRANCH', 'main')

def n8n_get(path):
    req = urllib.request.Request(
        f'{N8N_URL}{path}',
        headers={'X-N8N-API-KEY': N8N_KEY, 'Accept': 'application/json'}
    )
    return json.loads(urllib.request.urlopen(req, timeout=30).read())

def gh_get(path):
    try:
        req = urllib.request.Request(
            f'https://api.github.com{path}',
            headers={'Authorization': f'token {GH_TOKEN}', 'Accept': 'application/vnd.github.v3+json'}
        )
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise

def gh_put(path, body):
    req = urllib.request.Request(
        f'https://api.github.com{path}',
        data=json.dumps(body).encode(),
        method='PUT',
        headers={'Authorization': f'token {GH_TOKEN}', 'Content-Type': 'application/json'}
    )
    return json.loads(urllib.request.urlopen(req, timeout=15).read())

# Fetch all workflows
data = n8n_get('/api/v1/workflows?limit=200')
workflows = data.get('data', [])
print(f'Found {len(workflows)} workflows')

ok, fail = 0, 0
for wf in workflows:
    wid = wf['id']
    wname = wf['name']
    try:
        full = n8n_get(f'/api/v1/workflows/{wid}')
        safe_name = re.sub(r'[^\w\-]', '_', wname).strip('_')
        safe_name = re.sub(r'__+', '_', safe_name)
        filename = f'workflows/{safe_name}__{wid}.json'
        content_b64 = base64.b64encode(json.dumps(full, indent=2, ensure_ascii=False).encode('utf-8')).decode()
        existing = gh_get(f'/repos/{GH_REPO}/contents/{filename}')
        body = {
            'message': f'backup: {wname} [{wid}]',
            'content': content_b64,
            'branch': GH_BRANCH
        }
        if existing:
            body['sha'] = existing['sha']
        gh_put(f'/repos/{GH_REPO}/contents/{filename}', body)
        status = '✅ updated' if existing else '✅ created'
        print(f'{status}: {wname}')
        ok += 1
    except Exception as e:
        print(f'❌ FAILED: {wname} — {e}')
        fail += 1

print(f'\n🎉 Done: {ok} backed up, {fail} failed')
PYTHON
