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
    "collection": $eldts:collection-base || "{?id,page,nav}",
    "navigation": $eldts:navigation-base || "{?resource,ref,start,end,down,tree,page}",
    "document": $eldts:document-base || "{?resource,ref,start,end,tree,mediaType}"
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
    "collection": $eldts:collection-base || "{?id,page,nav}",
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
      "extensions": local:resource-extensions($tei),
      "mediaTypes": array { "application/xml", "text/plain" }
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
      "extensions": local:resource-extensions($tei),
      "mediaTypes": array { "application/xml", "text/plain" }
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
    "collection": $eldts:collection-base || "{?id,page,nav}",
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


(:
 : --------------------
 : Navigation Endpoint
 : --------------------
 :
 : https://dtsapi.org/specifications/versions/v1.0/#navigation-endpoint
 :)

(:~
 : DTS Navigation Endpoint
 :
 : Navigate within a text's citation tree.
 :
 : @param $resource Identifier of the resource (required)
 : @param $ref Single citation node identifier
 : @param $start Range start identifier
 : @param $end Range end identifier
 : @param $down Maximum depth relative to ref/start/end
 : @param $tree CitationTree identifier
 : @param $page Page number for paginated results
 : @result JSON-LD object
 :)
declare
  %rest:GET
  %rest:path("/eltec/v1/dts/navigation")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("down", "{$down}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("page", "{$page}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function eldts:navigation(
  $resource as xs:string*,
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $down as xs:string*,
  $tree as xs:string*,
  $page as xs:string*
) as item()+ {
  (: resource is required :)
  if (not($resource) or $resource = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'resource' is required." }
    )
  (: ref cannot combine with start/end :)
  else if ($ref and ($start or $end)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'ref' cannot be combined with 'start' and 'end'." }
    )
  (: start requires end and vice versa :)
  else if (($start and not($end)) or ($end and not($start))) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameters 'start' and 'end' must be used together." }
    )
  (: down=0 with start/end is not allowed :)
  else if ($down = "0" and ($start or $end)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'down=0' cannot be combined with 'start'/'end'." }
    )
  (: down=0 requires ref :)
  else if ($down = "0" and not($ref)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'down=0' requires 'ref'." }
    )
  (: no down, no ref, no start/end = bad request :)
  else if (not($down) and not($ref) and not($start)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "At least one of 'ref', 'start'/'end', or 'down' must be provided." }
    )
  else
    (: look up the resource :)
    let $tei := collection($config:corpora-root)//tei:TEI[@xml:id = $resource]
    return
      if (not($tei)) then
        (
          <rest:response><http:response status="404"/></rest:response>,
          map { "error": "Not Found", "message": "Resource '" || $resource || "' does not exist." }
        )
      else
        let $down-int := if ($down) then xs:integer($down) else ()
        return local:navigate($tei, $ref, $start, $end, $down-int, $page)
};

(:~
 : Build the Navigation response Resource object.
 :)
declare function local:navigation-resource($tei as element(tei:TEI))
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
      "navigation": $eldts:navigation-base || "?resource=" || $id || "{&amp;ref,start,end,down,tree,page}",
      "document": $eldts:document-base || "?resource=" || $id || "{&amp;ref,start,end,tree,mediaType}",
      "citationTrees": local:citation-trees($tei),
      "extensions": local:resource-extensions($tei),
      "mediaTypes": array { "application/xml", "text/plain" }
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
 : Build the @id for a Navigation response (the request URL).
 :)
declare function local:navigation-request-id(
  $resource as xs:string,
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $down as xs:integer*
) as xs:string {
  let $base := $eldts:navigation-base || "?resource=" || $resource
  let $params := string-join((
    if ($ref) then "&amp;ref=" || $ref else (),
    if ($start) then "&amp;start=" || $start else (),
    if ($end) then "&amp;end=" || $end else (),
    if (exists($down)) then "&amp;down=" || $down else ()
  ), "")
  return $base || $params
};

(:~
 : Main navigation dispatch.
 :)
declare function local:navigate(
  $tei as element(tei:TEI),
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $down as xs:integer*,
  $page as xs:string*
) as item()+ {
  let $id := $tei/@xml:id/string()
  let $request-id := local:navigation-request-id($id, $ref, $start, $end, $down)
  let $base-response := map {
    "@context": $eldts:jsonld-context,
    "@id": $request-id,
    "@type": "Navigation",
    "dtsVersion": $eldts:spec-version,
    "resource": local:navigation-resource($tei)
  }

  return
    (: ref without down: single CitableUnit info :)
    if ($ref and not(exists($down))) then
      let $elem := local:resolve-ref-to-element($tei, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Citation '" || $ref || "' not found." }
          )
        else
          map:merge(($base-response, map { "ref": local:citable-unit($ref, $elem) }))

    (: down=0 + ref: siblings :)
    else if ($down = 0 and $ref) then
      let $elem := local:resolve-ref-to-element($tei, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Citation '" || $ref || "' not found." }
          )
        else
          let $siblings := local:get-siblings($tei, $ref)
          return map:merge((
            $base-response,
            map { "ref": local:citable-unit($ref, $elem) },
            map { "member": array { $siblings } }
          ))

    (: down > 0, no ref: tree from root :)
    else if ($down > 0 and not($ref) and not($start)) then
      let $members := local:get-descendants-from-root($tei, $down)
      return map:merge((
        $base-response,
        map { "member": array { $members } }
      ))

    (: down > 0 + ref: tree from ref :)
    else if ($down > 0 and $ref) then
      let $elem := local:resolve-ref-to-element($tei, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Citation '" || $ref || "' not found." }
          )
        else
          let $members := local:get-descendants($tei, $ref, $down)
          return map:merge((
            $base-response,
            map { "ref": local:citable-unit($ref, $elem) },
            map { "member": array { $members } }
          ))

    (: down = -1: full tree :)
    else if ($down = -1 and not($ref) and not($start)) then
      let $members := local:get-full-tree($tei)
      return map:merge((
        $base-response,
        map { "member": array { $members } }
      ))

    (: down = -1 + ref: full tree from ref :)
    else if ($down = -1 and $ref) then
      let $elem := local:resolve-ref-to-element($tei, $ref)
      return
        if (empty($elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Citation '" || $ref || "' not found." }
          )
        else
          let $members := local:get-descendants($tei, $ref, -1)
          return map:merge((
            $base-response,
            map { "ref": local:citable-unit($ref, $elem) },
            map { "member": array { $members } }
          ))

    (: start/end without down: info about range endpoints :)
    else if ($start and $end and not(exists($down))) then
      let $start-elem := local:resolve-ref-to-element($tei, $start)
      let $end-elem := local:resolve-ref-to-element($tei, $end)
      return
        if (empty($start-elem) or empty($end-elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Range citation not found." }
          )
        else
          map:merge((
            $base-response,
            map {
              "start": local:citable-unit($start, $start-elem),
              "end": local:citable-unit($end, $end-elem)
            }
          ))

    (: start/end + down > 0 or down = -1: range with descendants :)
    else if ($start and $end and exists($down) and ($down > 0 or $down = -1)) then
      let $start-elem := local:resolve-ref-to-element($tei, $start)
      let $end-elem := local:resolve-ref-to-element($tei, $end)
      return
        if (empty($start-elem) or empty($end-elem)) then
          (
            <rest:response><http:response status="404"/></rest:response>,
            map { "error": "Not Found", "message": "Range citation not found." }
          )
        else
          let $members := local:get-range-members($tei, $start, $end, $down)
          return map:merge((
            $base-response,
            map {
              "start": local:citable-unit($start, $start-elem),
              "end": local:citable-unit($end, $end-elem)
            },
            map { "member": array { $members } }
          ))

    else
      (
        <rest:response><http:response status="400"/></rest:response>,
        map { "error": "Bad Request", "message": "Invalid parameter combination." }
      )
};

(:
 : --------------------
 : Citation Tree Helpers
 : --------------------
 :)

(:~
 : Validate an XPath-ish ref against a whitelist of safe patterns.
 :)
declare function local:validate-ref($ref as xs:string) as xs:boolean {
  matches($ref, "^(front|body|back)(/div\[\d+\])*(/p\[\d+\])?$")
  or matches($ref, "^front/div\[\d+\]$")
};

(:~
 : Resolve an XPath-ish ref to the actual TEI element.
 :
 : @param $tei TEI document
 : @param $ref XPath-ish identifier (e.g., "body/div[1]/p[3]")
 : @return The matching TEI element, or empty
 :)
declare function local:resolve-ref-to-element(
  $tei as element(tei:TEI),
  $ref as xs:string
) as element()* {
  if (not(local:validate-ref($ref))) then ()
  else
    let $xpath := "tei:text/tei:" || replace($ref, "/", "/tei:")
    return util:eval("$tei/" || $xpath)
};

(:~
 : Determine the citeType from a TEI element.
 :)
declare function local:get-cite-type($elem as element()) as xs:string {
  let $name := local-name($elem)
  return
    if ($name = "body") then "body"
    else if ($name = "front") then "front"
    else if ($name = "back") then "back"
    else if ($name = "p") then "paragraph"
    else if ($name = "div" and $elem/@type) then $elem/@type/string()
    else if ($name = "div") then "div"
    else $name
};

(:~
 : Get the level (depth) of a ref identifier.
 :)
declare function local:get-level($ref as xs:string) as xs:integer {
  count(tokenize($ref, "/"))
};

(:~
 : Get the parent ref from a ref identifier.
 : Returns empty string for top-level refs.
 :)
declare function local:get-parent-ref($ref as xs:string) as xs:string? {
  let $parts := tokenize($ref, "/")
  return
    if (count($parts) <= 1) then ()
    else string-join($parts[position() != last()], "/")
};

(:~
 : Build a CitableUnit object from a ref and its TEI element.
 :)
declare function local:citable-unit(
  $ref as xs:string,
  $elem as element()
) as map() {
  let $level := local:get-level($ref)
  let $parent := local:get-parent-ref($ref)
  let $cite-type := local:get-cite-type($elem)
  let $name := local-name($elem)

  (: paragraph-specific metadata :)
  let $p-num := if ($name = "p")
    then xs:integer(count($elem/preceding-sibling::tei:p) + 1)
    else ()

  let $snippet := if ($name = "p") then
    let $words := tokenize(normalize-space($elem), "\s+")
    return
      if (count($words) le 6) then
        string-join($words, " ")
      else
        string-join($words[position() le 5], " ")
        || " … "
        || $words[last()]
  else ()

  return map:merge((
    map {
      "identifier": $ref,
      "@type": "CitableUnit",
      "level": $level,
      "parent": if ($parent) then $parent else ()
    },
    map { "citeType": $cite-type },
    if ($elem/tei:head[1]) then
      map { "dublinCore": map { "title": normalize-space($elem/tei:head[1]) } }
    else (),
    if ($p-num) then
      let $word-count := count(tokenize(normalize-space($elem), "\s+"))
      return map { "extensions": map {
        "@context": $eldts:extensions-context-url,
        "paragraphNumber": $p-num,
        "snippet": $snippet,
        "wordCount": $word-count
      }}
    else ()
  ))
};

(:~
 : Generate a ref identifier for a child element within a parent context.
 :)
declare function local:generate-child-ref(
  $parent-ref as xs:string,
  $child as element()
) as xs:string {
  let $name := local-name($child)
  let $pos := count($child/preceding-sibling::*[local-name() = $name]) + 1
  return $parent-ref || "/" || $name || "[" || $pos || "]"
};

(:~
 : Get direct citable children of an element identified by ref.
 : Returns sequence of CitableUnit maps.
 :)
declare function local:get-citable-children(
  $tei as element(tei:TEI),
  $ref as xs:string
) as map()* {
  let $elem := local:resolve-ref-to-element($tei, $ref)
  return
    if (not($elem)) then ()
    else
      for $child in $elem/*[local-name() = ("div", "p")]
      let $child-ref := local:generate-child-ref($ref, $child)
      return local:citable-unit($child-ref, $child)
};

(:~
 : Get top-level citable units (body, front, back).
 :)
declare function local:get-top-level-units($tei as element(tei:TEI))
as map()* {
  let $text := $tei/tei:text
  return (
    if ($text/tei:front) then
      local:citable-unit("front", $text/tei:front)
    else (),
    if ($text/tei:body) then
      local:citable-unit("body", $text/tei:body)
    else (),
    if ($text/tei:back) then
      local:citable-unit("back", $text/tei:back)
    else ()
  )
};

(:~
 : Get descendants from root to a given depth.
 :)
declare function local:get-descendants-from-root(
  $tei as element(tei:TEI),
  $down as xs:integer
) as map()* {
  let $top := local:get-top-level-units($tei)
  return
    if ($down = 1) then $top
    else (
      for $unit in $top
      let $ref := $unit?identifier
      return (
        $unit,
        if ($down > 1) then
          local:get-descendants($tei, $ref, $down - 1)
        else ()
      )
    )
};

(:~
 : Get descendants of a ref to a given depth.
 : $depth = -1 means full depth.
 :)
declare function local:get-descendants(
  $tei as element(tei:TEI),
  $ref as xs:string,
  $depth as xs:integer
) as map()* {
  let $children := local:get-citable-children($tei, $ref)
  return
    if ($depth = 1) then $children
    else
      for $child in $children
      let $child-ref := $child?identifier
      return (
        $child,
        if ($depth = -1 or $depth > 1) then
          local:get-descendants(
            $tei, $child-ref,
            if ($depth = -1) then -1 else $depth - 1
          )
        else ()
      )
};

(:~
 : Get the full citation tree for a document.
 :)
declare function local:get-full-tree($tei as element(tei:TEI))
as map()* {
  let $top := local:get-top-level-units($tei)
  return
    for $unit in $top
    return (
      $unit,
      local:get-descendants($tei, $unit?identifier, -1)
    )
};

(:~
 : Get siblings of a ref (all children sharing the same parent).
 :)
declare function local:get-siblings(
  $tei as element(tei:TEI),
  $ref as xs:string
) as map()* {
  let $parent-ref := local:get-parent-ref($ref)
  return
    if (not($parent-ref)) then
      (: top level: siblings are front, body, back :)
      local:get-top-level-units($tei)
    else
      local:get-citable-children($tei, $parent-ref)
};


(:~
 : Get CitableUnits in a range between start and end, with descendants.
 :
 : Algorithm: produce the full ordered walk of the citation tree,
 : find start and end positions in that walk, slice inclusive,
 : then filter by depth budget. The depth budget is:
 :   max(level(start), level(end)) + down
 : or unlimited if down = -1.
 :
 : @param $tei TEI document
 : @param $start Start identifier
 : @param $end End identifier
 : @param $down Depth relative to the deeper endpoint (-1 = full depth)
 :)
declare function local:get-range-members(
  $tei as element(tei:TEI),
  $start as xs:string,
  $end as xs:string,
  $down as xs:integer
) as map()* {
  let $full-tree := local:get-full-tree($tei)

  (: find positions of start and end in the full walk :)
  let $start-pos := (
    for $unit at $pos in $full-tree
    where $unit?identifier = $start
    return $pos
  )[1]

  let $end-pos := (
    for $unit at $pos in $full-tree
    where $unit?identifier = $end
    return $pos
  )[1]

  (: find the last descendant of the end node — anything after end-pos
   : whose identifier starts with the end identifier is a descendant :)
  let $end-last := (
    for $unit at $pos in $full-tree
    where $pos > $end-pos
      and starts-with($unit?identifier, $end || "/")
    return $pos
  )
  let $slice-end := if (count($end-last)) then $end-last[last()] else $end-pos

  (: slice the walk between start and end inclusive, including end's descendants :)
  let $range := $full-tree[position() >= $start-pos and position() <= $slice-end]

  (: compute depth budget :)
  let $start-level := local:get-level($start)
  let $end-level := local:get-level($end)
  let $deeper-level := max(($start-level, $end-level))
  let $max-level := if ($down = -1) then 999 else $deeper-level + $down

  (: filter by depth budget :)
  return $range[.?level <= $max-level]
};


(:
 : --------------------
 : Document Endpoint
 : --------------------
 :
 : https://dtsapi.org/specifications/versions/v1.0/#document-endpoint
 :)

(:~
 : DTS Document Endpoint
 :
 : Retrieve full or partial TEI/XML content of a resource.
 :
 : @param $resource Identifier of the resource (required)
 : @param $ref Single citation node identifier
 : @param $start Range start identifier
 : @param $end Range end identifier
 : @param $tree CitationTree identifier
 : @param $media-type Requested media type
 : @result TEI/XML
 :)
declare
  %rest:GET
  %rest:path("/eltec/v1/dts/document")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("mediaType", "{$media-type}")
  %rest:produces("application/tei+xml", "application/xml")
  %output:media-type("application/xml")
  %output:method("xml")
function eldts:document(
  $resource as xs:string*,
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $tree as xs:string*,
  $media-type as xs:string*
) as item()+ {
  (: resource is required :)
  if (not($resource) or $resource = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      <error statusCode="400" xmlns="https://dtsapi.org/v1.0#">
        <title>Bad Request</title>
        <description>Parameter 'resource' is required.</description>
      </error>
    )
  (: ref cannot combine with start/end :)
  else if ($ref and ($start or $end)) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      <error statusCode="400" xmlns="https://dtsapi.org/v1.0#">
        <title>Bad Request</title>
        <description>Parameter 'ref' cannot be combined with 'start' and 'end'.</description>
      </error>
    )
  (: start requires end and vice versa :)
  else if (($start and not($end)) or ($end and not($start))) then
    (
      <rest:response><http:response status="400"/></rest:response>,
      <error statusCode="400" xmlns="https://dtsapi.org/v1.0#">
        <title>Bad Request</title>
        <description>Parameters 'start' and 'end' must be used together.</description>
      </error>
    )
  else
    let $tei := collection($config:corpora-root)//tei:TEI[@xml:id = $resource]
    return
      if (not($tei)) then
        (
          <rest:response><http:response status="404"/></rest:response>,
          <error statusCode="404" xmlns="https://dtsapi.org/v1.0#">
            <title>Not Found</title>
            <description>Resource '{$resource}' does not exist.</description>
          </error>
        )
      else if ($media-type and $media-type != "application/xml" and $media-type != "text/plain") then
        (
          <rest:response><http:response status="404"/></rest:response>,
          <error statusCode="404" xmlns="https://dtsapi.org/v1.0#">
            <title>Not Found</title>
            <description>Media type '{$media-type}' is not available. Supported: application/xml, text/plain.</description>
          </error>
        )
      else
        let $collection-link := $eldts:collection-base || "?id=" || $resource
        let $link-header := '&lt;' || $collection-link || '&gt;; rel="collection"'
        let $is-plain := ($media-type = "text/plain")
        return
          (: full document :)
          if (not($ref) and not($start)) then
            if ($is-plain) then
              (
                <rest:response>
                  <http:response status="200">
                    <http:header name="Link" value="{$link-header}"/>
                    <http:header name="Content-Type" value="text/plain; charset=utf-8"/>
                  </http:response>
                </rest:response>,
                local:element-to-plain-text($tei//tei:text)
              )
            else
              (
                <rest:response>
                  <http:response status="200">
                    <http:header name="Link" value="{$link-header}"/>
                    <http:header name="Content-Type" value="application/xml"/>
                  </http:response>
                </rest:response>,
                $tei
              )
          (: single fragment by ref :)
          else if ($ref) then
            let $elem := local:resolve-ref-to-element($tei, $ref)
            return
              if (empty($elem)) then
                (
                  <rest:response><http:response status="404"/></rest:response>,
                  <error statusCode="404" xmlns="https://dtsapi.org/v1.0#">
                    <title>Not Found</title>
                    <description>Citation '{$ref}' not found in resource '{$resource}'.</description>
                  </error>
                )
              else if ($is-plain) then
                (
                  <rest:response>
                    <http:response status="200">
                      <http:header name="Link" value="{$link-header}"/>
                      <http:header name="Content-Type" value="text/plain; charset=utf-8"/>
                    </http:response>
                  </rest:response>,
                  local:element-to-plain-text($elem)
                )
              else
                (
                  <rest:response>
                    <http:response status="200">
                      <http:header name="Link" value="{$link-header}"/>
                      <http:header name="Content-Type" value="application/xml"/>
                    </http:response>
                  </rest:response>,
                  <TEI xmlns="http://www.tei-c.org/ns/1.0">
                    { $tei/tei:teiHeader }
                    <text>
                      <body>
                        <dts:wrapper xmlns:dts="https://dtsapi.org/v1.0#" ref="{$ref}">
                          { $elem }
                        </dts:wrapper>
                      </body>
                    </text>
                  </TEI>
                )
          (: range by start/end :)
          else if ($start and $end) then
            let $start-elem := local:resolve-ref-to-element($tei, $start)
            let $end-elem := local:resolve-ref-to-element($tei, $end)
            return
              if (empty($start-elem) or empty($end-elem)) then
                (
                  <rest:response><http:response status="404"/></rest:response>,
                  <error statusCode="404" xmlns="https://dtsapi.org/v1.0#">
                    <title>Not Found</title>
                    <description>Range citations not found in resource '{$resource}'.</description>
                  </error>
                )
              else
                let $siblings := $start-elem/parent::*/*
                let $start-pos := count($start-elem/preceding-sibling::*) + 1
                let $end-pos := count($end-elem/preceding-sibling::*) + 1
                let $range := $siblings[position() >= $start-pos and position() <= $end-pos]
                return
                  if ($is-plain) then
                    (
                      <rest:response>
                        <http:response status="200">
                          <http:header name="Link" value="{$link-header}"/>
                          <http:header name="Content-Type" value="text/plain; charset=utf-8"/>
                        </http:response>
                      </rest:response>,
                      string-join(
                        for $r in $range return local:element-to-plain-text($r),
                        "&#xA;&#xA;"
                      )
                    )
                  else
                    (
                      <rest:response>
                        <http:response status="200">
                          <http:header name="Link" value="{$link-header}"/>
                          <http:header name="Content-Type" value="application/xml"/>
                        </http:response>
                      </rest:response>,
                      <TEI xmlns="http://www.tei-c.org/ns/1.0">
                        { $tei/tei:teiHeader }
                        <text>
                          <body>
                            <dts:wrapper xmlns:dts="https://dtsapi.org/v1.0#"
                              start="{$start}" end="{$end}">
                              { $range }
                            </dts:wrapper>
                          </body>
                        </text>
                      </TEI>
                    )
          else
            (
              <rest:response><http:response status="400"/></rest:response>,
              <error statusCode="400" xmlns="https://dtsapi.org/v1.0#">
                <title>Bad Request</title>
                <description>Invalid parameter combination.</description>
              </error>
            )
};

(:~
 : Convert a TEI element to plain text.
 :
 : Extracts text from head and p elements, joined by double newlines.
 : For a single p element, returns its normalized text content.
 :)
declare function local:element-to-plain-text($elem as element()) as xs:string {
  let $name := local-name($elem)
  return
    if ($name = "p") then
      normalize-space($elem)
    else
      string-join(
        $elem//(tei:head|tei:p) ! normalize-space(),
        "&#xA;&#xA;"
      )
};
