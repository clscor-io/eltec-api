xquery version "3.1";

(:~
 : Full-text search endpoint for the ELTeC API.
 :
 : Uses Lucene full-text indexing on tei:p elements with the standard analyzer.
 : Returns search results at paragraph level with KWIC context and
 : XPath-ish citable unit identifiers compatible with the DTS Navigation
 : and Document endpoints.
 :)
module namespace search = "http://eltec.clscor.io/ns/exist/search";

import module namespace config = "http://eltec.clscor.io/ns/exist/config"
  at "config.xqm";
import module namespace eltei = "http://eltec.clscor.io/ns/exist/tei"
  at "tei.xqm";
import module namespace elutil = "http://eltec.clscor.io/ns/exist/util"
  at "util.xqm";
import module namespace kwic = "http://exist-db.org/xquery/kwic";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Full-text search across ELTeC corpora.
 :
 : @param $q Search query string (required)
 : @param $corpus Corpus name to restrict search (optional)
 : @param $id Text identifier to restrict search to a single text (optional)
 : @param $limit Number of results per page (default: 20)
 : @param $offset Zero-based offset for pagination (default: 0)
 : @result JSON object with search results
 :)
declare
  %rest:GET
  %rest:path("/eltec/v1/search")
  %rest:query-param("q", "{$q}")
  %rest:query-param("corpus", "{$corpus}")
  %rest:query-param("id", "{$id}")
  %rest:query-param("limit", "{$limit}")
  %rest:query-param("offset", "{$offset}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function search:search(
  $q as xs:string*,
  $corpus as xs:string*,
  $id as xs:string*,
  $limit as xs:string*,
  $offset as xs:string*
) as item()+ {
  if (not($q) or $q = "") then
    (
      <rest:response><http:response status="400"/></rest:response>,
      map { "error": "Bad Request", "message": "Parameter 'q' is required." }
    )
  else

  let $lim := if ($limit) then xs:integer($limit) else 20
  let $off := if ($offset) then xs:integer($offset) else 0

  let $collection-path :=
    if ($corpus and $corpus != "")
    then $config:corpora-root || "/" || $corpus
    else $config:corpora-root

  (: check corpus exists :)
  return
    if ($corpus and not(xmldb:collection-available($collection-path))) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map { "error": "Not Found", "message": "Corpus '" || $corpus || "' does not exist." }
      )
    (: check text exists if id is provided :)
    else if ($id and not(collection($collection-path)//tei:TEI[@xml:id = $id])) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map { "error": "Not Found", "message": "Text '" || $id || "' does not exist." }
      )
    else

  let $hits :=
    if ($id) then
      collection($collection-path)//tei:TEI[@xml:id = $id]//tei:p[ft:query(., $q)]
    else
      collection($collection-path)//tei:p[ft:query(., $q)]
  let $total := count($hits)
  let $page := subsequence($hits, $off + 1, $lim)

  let $results := array {
    for $hit in $page
    let $tei := $hit/ancestor::tei:TEI
    let $id := $tei/@xml:id/string()
    let $titles := eltei:get-titles($tei)
    let $authors := eltei:get-authors($tei)
    let $paths := elutil:filepaths(base-uri($tei))
    let $citable-unit := local:build-citable-unit($hit)
    let $kwic := kwic:summarize($hit, <config width="40"/>)
    let $dts-base := $config:api-base || "/dts"
    let $ref-encoded := $citable-unit
    return map {
      "id": $id,
      "name": $paths?textname,
      "corpus": $paths?corpusname,
      "title": $titles?main,
      "authors": array { for $a in $authors return map { "name": $a?name } },
      "kwic": normalize-space(string-join($kwic//text(), "")),
      "collection": $dts-base || "/collection?id=" || $id,
      "document": $dts-base || "/document?resource=" || $id || "&amp;ref=" || $ref-encoded,
      "navigation": $dts-base || "/navigation?resource=" || $id || "&amp;ref=" || $ref-encoded
    }
  }

  return map {
    "query": $q,
    "totalHits": $total,
    "offset": $off,
    "limit": $lim,
    "results": $results
  }
};

(:~
 : Build an XPath-ish citable unit identifier for a tei:p element.
 :
 : Constructs the path from tei:text down to the paragraph,
 : e.g. "body/div[1]/div[2]/p[3]".
 :)
declare function local:build-citable-unit($p as element(tei:p)) as xs:string {
  let $ancestors := $p/ancestor-or-self::*[
    parent::tei:text or ancestor::tei:text
  ]
  return string-join(
    for $elem in $ancestors
    let $name := local-name($elem)
    return
      if ($name = ("body", "front", "back")) then
        $name
      else
        let $pos := count(
          $elem/preceding-sibling::*[local-name() = $name]
        ) + 1
        return $name || "[" || $pos || "]",
    "/"
  )
};
