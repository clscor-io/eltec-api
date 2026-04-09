xquery version "3.1";

(:~
 : DTS (Distributed Text Services) v1.0 Endpoints
 :
 : This module implements the DTS v1.0 API specification
 : (https://dtsapi.org/specifications/versions/v1.0/).
 :
 : Endpoints:
 : - Entry Point: /eltec/v1/dts
 : - Collections: /eltec/v1/dts/collection
 : - Navigation: /eltec/v1/dts/navigation
 : - Documents:  /eltec/v1/dts/document
 :)
module namespace eldts = "http://eltec.clscor.io/ns/exist/dts";

import module namespace config = "http://eltec.clscor.io/ns/exist/config"
  at "config.xqm";
import module namespace eltei = "http://eltec.clscor.io/ns/exist/tei"
  at "tei.xqm";
import module namespace elutil = "http://eltec.clscor.io/ns/exist/util"
  at "util.xqm";
import module namespace metrics = "http://eltec.clscor.io/ns/exist/metrics"
  at "metrics.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace dts = "https://dtsapi.org/v1.0#";

(: DTS v1.0 constants :)
declare variable $eldts:spec-version := "1.0";
declare variable $eldts:jsonld-context := "https://dtsapi.org/context/v1.0.json";

(: Extensions context URL :)
declare variable $eldts:extensions-context-url := $config:api-base || "/dts-extension-context.json";

(: Base URLs for DTS endpoints :)
declare variable $eldts:api-base := $config:api-base || "/dts";
declare variable $eldts:collection-base := $eldts:api-base || "/collection";
declare variable $eldts:navigation-base := $eldts:api-base || "/navigation";
declare variable $eldts:document-base := $eldts:api-base || "/document";

(:~
 : DTS Entry Point
 :
 : Provides discovery information for the DTS API endpoints.
 : https://dtsapi.org/specifications/versions/v1.0/#entry-endpoint
 :
 : @result JSON-LD object
 :)
declare
  %rest:GET
  %rest:path("/eltec/v1/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function eldts:entry-point()
as map() {
  map {
    "@context": $eldts:jsonld-context,
    "@id": $eldts:api-base,
    "@type": "EntryPoint",
    "dtsVersion": $eldts:spec-version,
    "collection": $eldts:collection-base || "/{?id,page,nav}",
    "navigation": $eldts:navigation-base || "/{?resource,ref,start,end,down,tree,page}",
    "document": $eldts:document-base || "/{?resource,ref,start,end,tree,mediaType}"
  }
};

(:
 : --------------------
 : Collection Endpoint
 : --------------------
 :
 : https://dtsapi.org/specifications/versions/v1.0/#collection-endpoint
 :)

(:~
 : DTS Collection Endpoint
 :
 : Navigate collections of corpora and texts.
 :
 : @param $id Identifier for a collection or resource
 : @param $page Page number for paginated results
 : @param $nav "children" (default) or "parents"
 : @result JSON-LD object
 :)
declare
  %rest:GET
  %rest:path("/eltec/v1/dts/collection")
  %rest:query-param("id", "{$id}")
  %rest:query-param("page", "{$page}")
  %rest:query-param("nav", "{$nav}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function eldts:collection(
  $id as xs:string*,
  $page as xs:string*,
  $nav as xs:string*
) as item()+ {
  (: validate nav parameter :)
  if ($nav and $nav != "children" and $nav != "parents") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map {
        "error": "Bad Request",
        "message": "Parameter 'nav' must be 'children' or 'parents'."
      }
    )
  else if (not($id) or $id = "") then
    (: no id: return root collection :)
    local:root-collection()
  else
    (: check if id matches a corpus name :)
    let $corpus := eltei:get-corpus($id)
    return
      if ($corpus) then
        if ($nav = "parents") then
          local:corpus-collection-with-parents($id)
        else
          local:corpus-collection($id)
      else
        (: check if id matches a text id (e.g. DEU001) :)
        let $tei := collection($config:corpora-root)//tei:TEI[@xml:id = $id]
        return
          if ($tei) then
            if ($nav = "parents") then
              local:resource-with-parents($tei)
            else
              local:resource($tei)
          else
            (
              <rest:response><http:response status="404"/></rest:response>,
              map {
                "error": "Not Found",
                "message": "The requested resource '" || $id || "' does not exist."
              }
            )
};

(:~
 : Root collection listing all corpora.
 :)
declare function local:root-collection()
as map() {
  let $corpora := collection($config:corpora-root)//tei:teiCorpus
  let $members := array {
    for $corpus in $corpora
    let $info := eltei:get-corpus-info($corpus)
    let $name := $info?name
    order by $name
    return local:corpus-member($info)
  }

  return map {
    "@context": $eldts:jsonld-context,
    "@id": "eltec",
    "@type": "Collection",
    "dtsVersion": $eldts:spec-version,
    "collection": $eldts:collection-base || "/{?id,page,nav}",
    "title": "ELTeC Corpora",
    "totalParents": 0,
    "totalChildren": count($members?*),
    "member": $members
  }
};

(:~
 : Build a member entry for a corpus in the root collection.
 :)
declare function local:corpus-member($info as map())
as map() {
  let $name := $info?name
  let $collection := concat($config:corpora-root, "/", $name)
  let $text-count := count(collection($collection)//tei:TEI)
  return map:merge((
    map {
      "@id": $name,
      "@type": "Collection",
      "title": $info?title,
      "collection": $eldts:collection-base || "?id=" || $name || "{&amp;page,nav}",
      "totalParents": 1,
      "totalChildren": $text-count,
      "extensions": local:corpus-extensions($name)
    },
    if ($info?description)
    then map:entry("description", $info?description) else ()
  ))
};

(:~
 : A single corpus as a collection, listing its texts as members.
 :)
declare function local:corpus-collection($corpusname as xs:string)
as map() {
  let $info := eltei:get-corpus-info-by-name($corpusname)
  let $teis := collection($config:corpora-root || "/" || $corpusname)//tei:TEI

  let $members := array {
    for $tei in $teis
    let $id := $tei/@xml:id/string()
    order by $id
    return local:resource-member($tei)
  }

  return map:merge((
    map {
      "@context": $eldts:jsonld-context,
      "@id": $corpusname,
      "@type": "Collection",
      "dtsVersion": $eldts:spec-version,
      "collection": $eldts:collection-base || "?id=" || $corpusname || "{&amp;page,nav}",
      "title": $info?title,
      "totalParents": 1,
      "totalChildren": count($teis),
      "member": $members,
      "extensions": local:corpus-extensions($corpusname)
    },
    if ($info?description)
    then map:entry("description", $info?description) else ()
  ))
};

(:~
 : Build a member entry for a text (Resource) within a corpus collection.
 :)
declare function local:resource-member($tei as element(tei:TEI))
as map() {
  let $id := $tei/@xml:id/string()
  let $titles := eltei:get-titles($tei)
  let $authors := eltei:get-authors($tei)
  let $lang := $tei/@xml:lang/string()
  let $title := local:display-title($titles, $authors)

  return map:merge((
    map {
      "@id": $id,
      "@type": "Resource",
      "title": $title,
      "collection": $eldts:collection-base || "?id=" || $id || "{&amp;nav}",
      "document": $eldts:document-base || "?resource=" || $id || "{&amp;ref,start,end,tree,mediaType}",
      "navigation": $eldts:navigation-base || "?resource=" || $id || "{&amp;ref,start,end,down,tree,page}",
      "totalParents": 1,
      "totalChildren": 0,
      "extensions": local:resource-extensions($tei)
    },
    if ($lang or count($authors)) then map:entry(
      "dublinCore", map:merge((
        if ($lang) then map:entry("language", array { $lang }) else (),
        if (count($authors))
        then map:entry("creator", array {
          for $a in $authors return $a?name
        })
        else ()
      ))
    ) else ()
  ))
};

(:~
 : A single text as a Resource with citationTrees.
 :)
declare function local:resource($tei as element(tei:TEI))
as map() {
  let $id := $tei/@xml:id/string()
  let $titles := eltei:get-titles($tei)
  let $authors := eltei:get-authors($tei)
  let $lang := $tei/@xml:lang/string()
  let $paths := elutil:filepaths(base-uri($tei))
  let $corpusname := $paths?corpusname
  let $title := local:display-title($titles, $authors)

  let $download := $config:api-base || "/corpora/" || $corpusname
    || "/texts/" || $paths?textname || "/tei"

  return map:merge((
    map {
      "@context": $eldts:jsonld-context,
      "@id": $id,
      "@type": "Resource",
      "dtsVersion": $eldts:spec-version,
      "title": $title,
      "collection": $eldts:collection-base || "?id=" || $id || "{&amp;nav}",
      "document": $eldts:document-base || "?resource=" || $id || "{&amp;ref,start,end,tree,mediaType}",
      "navigation": $eldts:navigation-base || "?resource=" || $id || "{&amp;ref,start,end,down,tree,page}",
      "totalParents": 1,
      "totalChildren": 0,
      "download": $download,
      "citationTrees": local:citation-trees($tei),
      "extensions": local:resource-extensions($tei)
    },
    if ($lang or count($authors)) then map:entry(
      "dublinCore", map:merge((
        if ($lang) then map:entry("language", array { $lang }) else (),
        if (count($authors))
        then map:entry("creator", array {
          for $a in $authors return $a?name
        })
        else ()
      ))
    ) else ()
  ))
};

(:~
 : Corpus collection with parent (root) as member via nav=parents.
 :)
declare function local:corpus-collection-with-parents($corpusname as xs:string)
as map() {
  let $info := eltei:get-corpus-info-by-name($corpusname)

  let $parent := map {
    "@id": "eltec",
    "@type": "Collection",
    "title": "ELTeC Corpora",
    "collection": $eldts:collection-base || "/{?id,page,nav}",
    "totalParents": 0,
    "totalChildren": count(collection($config:corpora-root)//tei:teiCorpus)
  }

  return map:merge((
    map {
      "@context": $eldts:jsonld-context,
      "@id": $corpusname,
      "@type": "Collection",
      "dtsVersion": $eldts:spec-version,
      "collection": $eldts:collection-base || "?id=" || $corpusname || "{&amp;page,nav}",
      "title": $info?title,
      "totalParents": 1,
      "totalChildren": count(collection($config:corpora-root || "/" || $corpusname)//tei:TEI),
      "member": array { $parent }
    },
    if ($info?description)
    then map:entry("description", $info?description) else ()
  ))
};

(:~
 : Single resource with parent (corpus) as member via nav=parents.
 :)
declare function local:resource-with-parents($tei as element(tei:TEI))
as map() {
  let $self := local:resource($tei)
  let $paths := elutil:filepaths(base-uri($tei))
  let $corpusname := $paths?corpusname
  let $corpus-info := eltei:get-corpus-info-by-name($corpusname)

  let $parent := map:merge((
    map {
      "@id": $corpusname,
      "@type": "Collection",
      "title": $corpus-info?title,
      "collection": $eldts:collection-base || "?id=" || $corpusname || "{&amp;page,nav}",
      "totalParents": 1,
      "totalChildren": count(collection($config:corpora-root || "/" || $corpusname)//tei:TEI)
    }
  ))

  return map:merge((
    map:remove($self, "member"),
    map:entry("member", array { $parent })
  ))
};

(:~
 : Build extensions metadata for a corpus.
 :
 : @param $corpusname Corpus name
 :)
declare function local:corpus-extensions($corpusname as xs:string)
as map() {
  let $m := metrics:corpus($corpusname)
  return map {
    "@context": $eldts:extensions-context-url,
    "numOfTexts": $m?numOfTexts,
    "numOfAuthors": $m?numOfAuthors,
    "numOfWords": $m?numOfWords,
    "numOfParagraphs": $m?numOfParagraphs
  }
};

(:~
 : Build extensions metadata for a text.
 :
 : @param $tei TEI element
 :)
declare function local:resource-extensions($tei as element(tei:TEI))
as map() {
  let $paths := elutil:filepaths(base-uri($tei))
  let $m := metrics:text($paths?corpusname, $paths?textname)
  let $authors := eltei:get-authors($tei)

  (: collect author Wikidata IDs :)
  let $author-wikidata-ids :=
    for $a in $authors
    for $ref in $a?refs?*
    where starts-with($ref, "wikidata:")
    return substring-after($ref, "wikidata:")

  (: text Wikidata ID :)
  let $text-ref := $tei//tei:fileDesc/tei:titleStmt/tei:title/@ref/string()
  let $text-wikidata := if (starts-with($text-ref, "wikidata:"))
    then substring-after($text-ref, "wikidata:")
    else ()

  return map:merge((
    map { "@context": $eldts:extensions-context-url },
    map { "numOfWords": $m?numOfWords },
    map { "numOfParagraphs": $m?numOfParagraphs },
    map { "numOfChapters": $m?numOfChapters },
    if ($text-wikidata) then map { "wikidataId": $text-wikidata } else (),
    if (count($author-wikidata-ids))
    then map { "authorWikidataIds": array { $author-wikidata-ids } }
    else ()
  ))
};

(:~
 : Construct a display title combining author name(s) and title.
 :
 : @param $titles Map with title info from eltei:get-titles
 : @param $authors Sequence of author maps from eltei:get-authors
 :)
declare function local:display-title(
  $titles as map(),
  $authors as map()*
) as xs:string {
  let $author-str := string-join(
    for $a in $authors return $a?name, "; "
  )
  return
    if ($author-str) then
      $author-str || ": " || $titles?main
    else
      $titles?main
};

(:~
 : Generate citationTrees for a TEI document.
 :
 : Inspects the actual structure of the TEI body to build
 : the appropriate citeStructure hierarchy.
 :)
declare function local:citation-trees($tei as element(tei:TEI))
as array(*) {
  array {
    map {
      "@type": "CitationTree",
      "citeStructure": local:cite-structure($tei)
    }
  }
};

(:~
 : Generate citeStructure based on actual TEI structure.
 :)
declare function local:cite-structure($tei as element(tei:TEI))
as array(*) {
  let $body := $tei/tei:text/tei:body
  let $front := $tei/tei:text/tei:front
  let $back := $tei/tei:text/tei:back

  return array {
    (: front :)
    if ($front) then
      map:merge((
        map { "@type": "CiteStructure", "citeType": "front" },
        if ($front/tei:div) then
          map:entry("citeStructure", array {
            map { "@type": "CiteStructure", "citeType": "liminal" }
          })
        else ()
      ))
    else (),

    (: body :)
    if ($body) then
      map:merge((
        map { "@type": "CiteStructure", "citeType": "body" },
        map:entry("citeStructure", local:body-cite-structure($body))
      ))
    else (),

    (: back :)
    if ($back) then
      map { "@type": "CiteStructure", "citeType": "back" }
    else ()
  }
};

(:~
 : Generate citeStructure for the body element.
 :
 : Detects the actual nesting pattern (flat chapters, grouped, nested groups,
 : or paragraphs only).
 :)
declare function local:body-cite-structure($body as element(tei:body))
as array(*) {
  let $p-struct := map { "@type": "CiteStructure", "citeType": "paragraph" }

  let $chapter-struct := map:merge((
    map { "@type": "CiteStructure", "citeType": "chapter" },
    if ($body//tei:div[@type="chapter"]/tei:p) then
      map:entry("citeStructure", array { $p-struct })
    else ()
  ))

  return
    (: body has div[@type="group"] with nested div[@type="group"] :)
    if ($body/tei:div[@type="group"]/tei:div[@type="group"]) then
      array {
        map {
          "@type": "CiteStructure",
          "citeType": "group",
          "citeStructure": array {
            map {
              "@type": "CiteStructure",
              "citeType": "group",
              "citeStructure": array { $chapter-struct }
            }
          }
        }
      }
    (: body has div[@type="group"] with div[@type="chapter"] :)
    else if ($body/tei:div[@type="group"]/tei:div[@type="chapter"]) then
      array {
        map {
          "@type": "CiteStructure",
          "citeType": "group",
          "citeStructure": array { $chapter-struct }
        }
      }
    (: body has div[@type="chapter"] directly :)
    else if ($body/tei:div[@type="chapter"]) then
      array { $chapter-struct }
    (: body has only paragraphs :)
    else if ($body/tei:p) then
      array { $p-struct }
    (: fallback: generic div structure :)
    else
      array {
        map { "@type": "CiteStructure", "citeType": "div" }
      }
};
