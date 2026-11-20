"""Check static page links, local assets, ids, image credits, and HTML language."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit,unquote
import json
ROOT=Path(__file__).resolve().parents[1]/'site'
class Page(HTMLParser):
 def __init__(self):super().__init__();self.links=[];self.ids=[];self.lang=None
 def handle_starttag(self,tag,attrs):
  d=dict(attrs)
  if tag=='html':self.lang=d.get('lang')
  if d.get('id'):self.ids.append(d['id'])
  for key in ('href','src'):
   if d.get(key):self.links.append(d[key])
  if tag=='img':assert 'alt' in d,'Missing image alt'
pages={}
for path in ROOT.rglob('*.html'):
 page=Page();page.feed(path.read_text());assert page.lang=='en',path
 assert len(page.ids)==len(set(page.ids)),f'Duplicate id: {path}'
 pages[path.resolve()]=page
for path,page in pages.items():
 for link in page.links:
  u=urlsplit(link)
  if u.scheme or u.netloc:continue
  target=(ROOT/u.path.lstrip('/') if u.path.startswith('/') else path.parent/unquote(u.path)).resolve() if u.path else path
  assert target.exists(),f'Missing local link: {path.name}: {link}'
  if target in pages and u.fragment:assert unquote(u.fragment) in pages[target].ids,f'Missing fragment: {path.name}: {link}'
credits=json.loads((ROOT/'assets/photos/credits.json').read_text())
assert len(credits)==8
for c in credits:
 assert (ROOT/c['file']).exists()
 assert c['author'] and c['license'] and c['source'].startswith('https://commons.wikimedia.org/')
print(f'PASS: {len(pages)} pages; all internal links, anchors, image alts and 8 image credits verified.')
