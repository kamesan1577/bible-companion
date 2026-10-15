"""Preserve SWORD chapter-zero material without calling it verse-by-verse commentary."""
import hashlib,re,html

def digest(value):return hashlib.sha256(value.encode()).hexdigest()

def make_contexts(rows,edition,book_names,counts,plain):
    by_name={name:book for book,name in book_names.items()};out=[];seen=set()
    for locator,markup in rows:
        match=re.fullmatch(r'(.+) (\d+):0',locator)
        if not match:continue
        name,chapter=match[1],int(match[2]);book=by_name.get(name)
        # Book-level introductions at0:0 have a different scope and are not expanded.
        if book is None or not 1<=chapter<=len(counts[book]):continue
        text=plain(markup)
        if not text:continue
        assert (book,chapter)not in seen;seen.add((book,chapter))
        references=list(dict.fromkeys(html.unescape(x)for x in re.findall(r'osisRef=["\']([^"\']+)["\']',markup)))
        cross=[]
        # Explicitly verified parallel-chapter reference; no automatic verse alignment.
        if book=='2SA'and chapter==22:
            target=next((x for x in references if re.fullmatch(r'Ps\.18\.1(?:-Ps\.18\.50)?',x)),None)
            if target:
                cross=[{'passage':{'book':'PSA','start':{'chapter':18,'verse':1},'end':{'chapter':18,'verse':counts['PSA'][17]}},'sourceReference':target,'relation':'parallel-chapter-commentary; not verse alignment','noteJa':'原典は詩篇18章の注解を参照しています。サムエル記下22章との節対応を自動的に同一視しません。'}]
        out.append({'id':edition.lower()+':chapter-context:'+digest(locator+'\0'+markup),'editionId':edition+'-'+('2.2'if edition=='MHC'else'3.0'),'sourceLocator':locator,'ranges':[{'book':book,'start':{'chapter':chapter,'verse':1},'end':{'chapter':chapter,'verse':counts[book][chapter-1]}}],'originalText':text,'originalMarkupSha256':digest(markup),'language':'en','kind':'chapter-context','scopeMeaning':'chapter-level retrieval scope; not independent commentary on each verse','sourceReferences':references,'crossReferences':cross,'reviewStatus':'original-chapter-context-converted-not-editorially-reviewed','spoilerSafe':False})
    return out

def scope_coordinates(contexts):
    return {f"{r['book']}:{r['start']['chapter']}:{v}"for u in contexts for r in u['ranges']for v in range(r['start']['verse'],r['end']['verse']+1)}
