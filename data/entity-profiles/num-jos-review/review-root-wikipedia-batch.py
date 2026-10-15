from pathlib import Path
import json,hashlib,datetime
N=Path(__file__).resolve().parent;sha=lambda b:hashlib.sha256(b).hexdigest();A=N/'reviews/current-wikipedia-places3-root-batch.json';assignment=json.loads(A.read_text())
observations={
'Bethoron':('Lead 126–129; History / Iron Age 154; Ascent 146','隣接する上・下の二町を分け、上町をJoshua16:5、下町を16:3へ明示的に対応させる。現代村名Fauqa/Tahtaの対応も逆転していない。','pass'),
'Mount_Seir':('Lead 129–131; Hebrew Bible 138; Southern land 143–151; Northern Mount Seir 152–156','南部Edomの山地とJoshua15:10の北側同名山を区別する。北側についてSa’ir近傍説も掲載するので、元の「比定を示さない」は誤り。作者修正後noteは記事の区別と比定説の不確実性を正しく限定する。','qualified'),
'Achshaph':('Lead 114; Location 115–119','北Canaanの王都、Joshua11:1/12:20/19:25を対応させ、Tell Keisanを含む複数の位置説を列挙する。作者の現稿は王と町を文法的にも区別する。','pass'),
'Akrabbim':('Lead 112; Maaleh-acrabbim in Judges 113–117','死海南方・Zin間の峠を含む尾根の呼称として可能性付きで説明し、Joshua15:3/Numbers34:4を挙げる。Judgesの同名用法は別節で区別している。','qualified'),
'Ashdod_(ancient_city)':('Lead 138–142; Archaeology 322–325','古代都市の遺跡Tel Ashdodを現代Ashdod市街地の南の地点として明記し、アプリnoteの古代町と現代市の区別を支持する。','qualified'),
'Azekah':('Biblical history / Joshua 149–153; Identification 165–174','Joshua10の追撃に登場する町と結び、Tel Azekah/Tell Zakariyeh同定の経緯と異論・別候補を掲載する。noteはその留保を保持する。','qualified'),
'Bamoth-Baal':('Lead and location paragraphs 106–108','Moabの高所として扱い、Joshua13:17のReuben町一覧と結ぶ。複数の候補位置説は説として述べる。','qualified'),
'Beeroth_(biblical_city)':('Lead 119; Identification 120–127','Joshua9:17と18:25の町を扱い、Deuteronomy10:6の同名町を別とする。Gibeonとの関係および複数の位置候補を説明し、現noteは区別を正しく示す。','qualified'),
'Beth-zur':('Lead 129–131; In the Hebrew Bible 165–167','Hebron山地の古代地として扱い、Khirbet et-Tubeiqa同定とJoshua15:58のHalhul/Beth-Zur/Gedorの並びを明記する。','qualified'),
'Beth_Shemesh':('Unheaded lead and four-place list 103–107','同名の四対象を分け、Issacharの町をJoshua19:22に明示し、Ain esh-Shemsiyehを可能性として挙げる。作者修正後shared-sectionという分類と現noteは該当行に合う。','qualified')}
fixed={ (x['canonical']['chapter'],x['canonical']['verse']):x for x in json.loads((N/'inventory/targets/joshua-web-verses.json').read_text())};records=[];urls=[]
for group in assignment['assignments']:
 key=group['url'].split('/wiki/')[1];locator,paraphrase,status=observations[key]
 urls.append({'url':group['url'],'renderedArticleLocator':locator,'bodyRead':True,'evidenceParaphraseJa':paraphrase,'status':status,'license':'CC BY-SA 4.0','attribution':'Wikipedia contributors','bodySHA256':None,'bodyHashNoteJa':'web toolの描画本文を実読。取得HTMLそのもののバイト列を返さないためbody hashは捏造しない。'})
 for row in group['profiles']:
  f=N/row['draftPath'];d=json.loads(f.read_text());p=d['profile'];pos=(p['knownBy']['chapter'],p['knownBy']['verse']);witness=fixed[pos];e=N/'evidence/places_3'/f.name
  records.append({'entityID':p['id'],'draftPath':row['draftPath'],'currentDraftSHA256':sha(f.read_bytes()),'currentEvidenceSHA256':sha(e.read_bytes()),'wikipedia':p['wikipedia'],'wikipediaURLMatchesReadArticle':p['wikipedia']['url']==group['url'],'actualArticleRead':True,'articleEvidenceLocator':locator,'identityOrRelationVerdict':status,'articleEvidenceParaphraseJa':paraphrase,'firstUseWitness':{'ref':f'JOS {pos[0]}:{pos[1]}','url':witness['citationURL'],'text':witness['text'],'textSHA256':sha(witness['text'].encode())},'primaryFirstUseFieldsChecked':True,'coordinatePromoted':False})
assert len(records)==12 and len(urls)==10 and all(r['wikipediaURLMatchesReadArticle']for r in records)
report={'reviewType':'root independent actual article-body check of assigned places3 links','reviewedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'assignmentPath':str(A.relative_to(N)),'assignmentSHA256':sha(A.read_bytes()),'scope':{'uniqueURLs':10,'profiles':12,'articleBodiesRead':10,'sourceFirstUsesRead':12},'methodJa':'リンク到達やタイトル一致だけでなく、web toolで現記事の該当段落・表項目を実読し、current note/対象区別と固定WEB初出を照合。自身は対象の原稿作者ではない。','urls':urls,'records':records,'authorCorrectionsIndependentlyRechecked':['Mount Seir誤った比定否定の除去','Achshaph王と町の文法的区別','Beth Shemeshを複数同名地のshared-sectionへ分類'],'unresolvedContentFailures':[],'limitationsJa':['記事の歴史的主張すべてを保証したものではない。候補点の独立地理検証や専門家校閲は行っていない。','Ashdod記事Biblical references319行のJoshua11をJudahの割当とする記述は固定WEB11:22と一致しない。アプリは原典に従ってAnakim残留のみ記しており、この二次資料の誤記を採用しない。','北側Mount SeirのSa’ir比定は記事上の説としてのみ取り扱い、アプリの確定位置へ昇格しない。']}
O=N/'reviews/root-current-wikipedia-places3-closure.json';O.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'report':str(O.relative_to(N)),'sha256':sha(O.read_bytes()),'urls':10,'profiles':12,'failures':0}))
