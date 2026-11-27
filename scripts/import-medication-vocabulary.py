#!/usr/bin/env python3
"""Build a compact, offline human-medication vocabulary from official Health Canada DPD extracts."""
import argparse,csv,hashlib,io,json,urllib.request,zipfile
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--cache',type=Path,default=ROOT/'build/dpd')
p.add_argument('--source-date',required=True,help='Publication date shown by Health Canada; recorded, not inferred from ZIP timestamps.')
a=p.parse_args();a.cache.mkdir(parents=True,exist_ok=True)
base='https://www.canada.ca/content/dam/hc-sc/documents/services/drug-product-database/'
manifest={'source':'Health Canada Drug Product Database','publicationDate':a.source_date,'scope':'Marketed human drugs only; names and ingredient vocabulary, not interaction or prescribing guidance','files':{}}
def rows(kind):
 path=a.cache/(kind+'.zip')
 if not path.exists():path.write_bytes(urllib.request.urlopen(base+kind+'.zip',timeout=60).read())
 data=path.read_bytes();manifest['files'][kind]={'url':base+kind+'.zip','sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
 with zipfile.ZipFile(io.BytesIO(data)) as archive:
  filename=next(n for n in archive.namelist() if n.endswith('.txt'))
  return list(csv.reader(io.StringIO(archive.read(filename).decode('utf-8-sig'))))
products=[r for r in rows('drug') if r[2]=='Human'];human={r[0] for r in products}
ingredients=defaultdict(set);generic={}
for row in rows('ingred'):
 if row[0] not in human:continue
 english=row[2].strip();french=row[11].strip() if len(row)>11 else ''
 if not english:continue
 ingredients[row[0]].add(english)
 # Parenthesized supplied salt is kept in the ingredient field; the name prefix is an alias only.
 label=english.split(' (')[0];label_fr=(french or english).split(' (')[0]
 key='ingredient:'+row[1]
 generic.setdefault(key,{'id':'dpd-'+key,'name':label,'fr':label_fr,'aliases':set(),'ingredients':{english}})
 generic[key]['aliases'].update([english,french,label,label_fr])
# Explicit familiar-name alias, scoped to one verified DPD ingredient identity.
# https://produits-sante.canada.ca/dpd-bdpp/info?code=19595&lang=eng
# This adds names only; it never strips salts from the actual ingredient composition.
if 'ingredient:5325' in generic:
 generic['ingredient:5325']['aliases'].update(['levothyroxine','lévothyroxine'])
brands=defaultdict(lambda:{'aliases':set(),'compositions':set()})
for row in products:
 name=row[4].strip();fr=row[12].strip() if len(row)>12 else ''
 composition=tuple(sorted(ingredients[row[0]]))
 if not name or not composition:continue
 item=brands[name];item['aliases'].update([name,fr]);item['compositions'].add(composition)
entries=list(generic.values());ambiguous=0
for name,item in sorted(brands.items()):
 if len(item['compositions'])!=1:ambiguous+=1;continue
 entries.append({'id':'dpd-brand:'+hashlib.sha256(name.encode()).hexdigest()[:20],'name':name,'fr':next((x for x in sorted(item['aliases']) if x!=name),name),'aliases':item['aliases'],'ingredients':set(next(iter(item['compositions'])))})
for item in entries:
 item['aliases']=sorted(x for x in item['aliases'] if x)
 item['ingredients']=sorted(item['ingredients'])
entries.sort(key=lambda r:r['id'])
data=json.dumps({'version':1,'publicationDate':a.source_date,'entries':entries},ensure_ascii=False,separators=(',',':')).encode()
out=ROOT/'HarbourCore/Sources/HarbourCore/Resources/medication-vocabulary.json';out.write_bytes(data)
manifest.update({'humanProducts':len(products),'ingredientEntries':len(generic),'uniqueCompositionBrandEntries':len(entries)-len(generic),'ambiguousBrandNamesExcluded':ambiguous,'entries':len(entries),'resourceBytes':len(data),'resourceSHA256':hashlib.sha256(data).hexdigest()})
(ROOT/'docs/medication-vocabulary-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({k:v for k,v in manifest.items() if k not in ['files']},ensure_ascii=False))
