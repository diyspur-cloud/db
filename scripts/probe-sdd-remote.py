#!/usr/bin/env python3
"""Probes sem cadastro, DML, mensagens ou pagamentos; publica somente status/erros."""
import concurrent.futures
import datetime
import json
import os
import pathlib
import urllib.error
import urllib.request

URL = 'https://xjhehhfhhoomblcggjpk.supabase.co'
KEY = os.environ.get('DIYSPUR_PUBLISHABLE_KEY', '')
if not KEY:
    raise SystemExit('Defina DIYSPUR_PUBLISHABLE_KEY com a chave pública do projeto.')
FUNCTIONS = ['quiz-validate', 'award-xp', 'vote-next-book', 'scheduled-reminders',
             'ai-recommendations', 'ai-user-embeddings', 'match-readers',
             'newsletter-dispatch', 'stripe-webhook', 'social-render-card']
ROUTES = ['/rest/v1/' + table + '?select=*&limit=0' for table in
          ['buddy_reads', 'buddy_read_members', 'buddy_read_checkpoints',
           'reading_lists', 'reading_list_collaborators', 'reading_list_items']]
ROUTES += ['/rest/v1/rpc/is_admin',
           '/rest/v1/v_book_community_stats?select=mood_percent,sample_size,ratings_count,avg_spice_level&limit=0',
           '/rest/v1/v_club_progress_panel?select=finished_count,reading_count,not_started_count&limit=0',
           '/auth/v1/settings']
ROUTES += ['/functions/v1/' + fn for fn in FUNCTIONS]

def probe(path):
    request = urllib.request.Request(URL + path, headers={'apikey': KEY})
    try:
        response = urllib.request.urlopen(request, timeout=30)
        status, text = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode()
    except Exception as error:
        return {'path': path, 'status': None, 'error': type(error).__name__}
    try:
        body = json.loads(text)
    except json.JSONDecodeError:
        body = text[:200]
    if path == '/auth/v1/settings':
        body = {'external': body.get('external', {})}
    return {'path': path, 'status': status, 'body': body}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(probe, ROUTES))
output = {'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'project': URL, 'method': 'GET; sem identidade de usuário', 'results': results}
path = pathlib.Path(__file__).resolve().parents[1] / 'docs/execution/remote/http-probes-latest.json'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
for item in results:
    print(item['status'], item['path'])
print('Evidência:', path)
