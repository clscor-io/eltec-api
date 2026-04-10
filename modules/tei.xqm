xquery version "3.1";

(:~
 : Module providing TEI extraction functions for ELTeC.
 :)
module namespace eltei = "http://eltec.clscor.io/ns/exist/tei";

import module namespace config = "http://eltec.clscor.io/ns/exist/config" at "config.xqm";
import module namespace elutil = "http://eltec.clscor.io/ns/exist/util" at "util.xqm";
import module namespace metrics = "http://eltec.clscor.io/ns/exist/metrics" at "metrics.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace eltec = "http://distantreading.net/eltec/ns";

declare variable $eltei:ids := doc('/db/eltec/ids.xml');
declare variable $eltei:authors := doc('/db/eltec/authors.xml');

(:~
 : Get teiCorpus element for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return teiCorpus element
 :)
declare function eltei:get-corpus(
  $corpusname as xs:string
) as element()* {
  collection($config:corpora-root)//tei:teiCorpus[
    tei:teiHeader//tei:publicationStmt/tei:idno[not(@type) and . = $corpusname]
  ]
};

(:~
 : Extract DraCor ID of a text.
 :
 : @param $tei TEI document
 :)
declare function eltei:get-eltec-id($tei as element(tei:TEI)) as xs:string* {
  $tei/@xml:id/normalize-space()
};

(:~
 : Strip the ELTeC edition label suffix from a title.
 :
 : ELTeC TEI files put a language-specific edition label
 : (e.g. "ELTeC ausgabe", "ELTeC edition", "édition ELTeC",
 : "edición ELTeC", "Edição para o ELTeC", "vydání ELTeC",
 : "edicija ELTeC", "ediție ELTeC", "ELTeC kiadás", "ELTeC издање",
 : "(vydání ELTeC)", ...) into tei:titleStmt/tei:title.
 : This helper removes that suffix so API consumers see a clean title.
 :
 : Applied iteratively to handle pathological double suffixes such as
 : "Mark Rutherford's Deliverance : ELTec edition : ELTeC edition"
 : that occur in some corpora.
 :
 : @param $title A raw title string
 : @return The title with any trailing ELTeC edition label removed
 :)
declare function eltei:strip-edition-label(
  $title as xs:string?
) as xs:string? {
  if (empty($title)) then $title
  else
    let $patterns := (
      (: project-name-first labels, e.g. "ELTeC ausgabe", "ELTeC edition",
       : "ELTeC kiadás", "ELTeC издање", and the typo "ELTec edition" :)
      "\s*[:(]?\s*(?:ELTec|ELTeC)\s+(?:[Aa]usgabe|[Ee]dition|kiadás|издање)\s*\)?\s*$",

      (: language-word-first labels, e.g. "édition ELTeC",
       : "edición ELTeC", "Edição para o ELTeC", "vydání ELTeC",
       : "edicija ELTeC", "ediție ELTeC". The optional "(" / ")" handles
       : the parenthesised Czech form "(vydání ELTeC)". :)
      "\s*[:(]?\s*(?:édition|[Ee]dición|[Ee]dicija|[Ee]di[țt]ie|[Ee]dição\s+para\s+o|[Vv]ydání)\s+(?:ELTeC|ELTEC)\s*\)?\s*$"
    )

    let $stripped :=
      fold-left(
        $patterns,
        $title,
        function ($acc as xs:string, $pattern as xs:string) as xs:string {
          if (matches($acc, $pattern)) then replace($acc, $pattern, "")
          else $acc
        }
      )

    return
      if ($stripped = $title) then normalize-space($stripped)
      else eltei:strip-edition-label($stripped)
};

(:~
 : Extract title and subtitle.
 :
 : @param $tei TEI document
 :)
declare function eltei:get-titles( $tei as element(tei:TEI) ) as map() {
  let $title := eltei:strip-edition-label(
    $tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space()
  )
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Retrieve title and subtitle from TEI by language.
 :
 : @param $tei TEI document
 : @param $lang 3-letter language code
 :)
declare function eltei:get-titles(
  $tei as element(tei:TEI),
  $lang as xs:string
) as map() {
  if($lang = $tei/@xml:lang) then
    eltei:get-titles($tei)
  else
  let $title := eltei:strip-edition-label(
    $tei//tei:fileDesc/tei:titleStmt
      /tei:title[@xml:lang = $lang and not(@type = 'sub')][1]
      /normalize-space()
  )
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type = 'sub' and @xml:lang = $lang][1]
      /normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Extract text paragraphs.
 :
 : @param $tei TEI document
 :)
declare function eltei:get-text-paras($tei as element(tei:TEI)) as element(tei:p)* {
  $tei//tei:text//tei:p[@xml:id]
};

(:~
 : Extract Wikidata ID for play from standOff.
 :
 : @param $tei TEI element
 :)
declare function eltei:get-text-wikidata-id ($tei as element(tei:TEI)) {
  let $uri := $tei//tei:standOff/tei:listRelation
    /tei:relation[@name="wikidata"][1]/@passive/string()
  return if (starts-with($uri, 'http://www.wikidata.org/entity/')) then
    tokenize($uri, '/')[last()]
  else ()
};

(:~
 : Extract ELTeC classification metadata.
 :
 : Returns the four balance criteria from the eltec: namespace elements
 : under tei:profileDesc/tei:textDesc.
 :
 : @param $tei TEI element
 : @return map with authorGender, sizeCategory, timeSlot, reprintCount
 :)
declare function eltei:get-eltec-classification(
  $tei as element(tei:TEI)
) as map() {
  let $textDesc := $tei//tei:profileDesc/tei:textDesc
  return map:merge((
    if ($textDesc/eltec:authorGender/@key)
      then map:entry("authorGender", string($textDesc/eltec:authorGender/@key))
      else (),
    if ($textDesc/eltec:size/@key)
      then map:entry("sizeCategory", string($textDesc/eltec:size/@key))
      else (),
    if ($textDesc/eltec:timeSlot/@key)
      then map:entry("timeSlot", string($textDesc/eltec:timeSlot/@key))
      else (),
    if ($textDesc/eltec:reprintCount/@key)
      then map:entry("reprintCount", string($textDesc/eltec:reprintCount/@key))
      else if ($textDesc/eltec:canonicity/@key)
      then map:entry("reprintCount", string($textDesc/eltec:canonicity/@key))
      else ()
  ))
};

(:~
 : Extract a reference year for a text.
 :
 : Priority: first edition > print source > digital source.
 :
 : @param $tei TEI element
 : @return year string or empty
 :)
declare function eltei:get-reference-year(
  $tei as element(tei:TEI)
) as xs:string? {
  let $sourceDesc := $tei/tei:teiHeader/tei:fileDesc/tei:sourceDesc
  let $firstEd := $sourceDesc//tei:bibl[@type='firstEdition']/tei:date
  let $printSrc := $sourceDesc//tei:bibl[@type='printSource']/tei:date
  let $digitalSrc := $sourceDesc//tei:bibl[@type='digitalSource']/tei:date
  return
    if ($firstEd) then eltei:get-year($firstEd[1])
    else if ($printSrc) then eltei:get-year($printSrc[1])
    else if ($digitalSrc) then eltei:get-year($digitalSrc[1])
    else ()
};

(:~
 : Extract full name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function eltei:get-full-name ($author as element(tei:author)) {
  if ($author/tei:persName) then
    normalize-space($author/tei:persName[1])
  else if ($author/tei:name) then
    normalize-space($author/tei:name[1])
  else normalize-space($author)
};

(:~
 : Extract full name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function eltei:get-full-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  if ($author/tei:persName[@xml:lang=$lang]) then
    normalize-space($author/tei:persName[@xml:lang=$lang][1])
  else if ($author/tei:name[@xml:lang=$lang]) then
    normalize-space($author/tei:name[@xml:lang=$lang][1])
  else ()
};

declare function local:build-short-name ($name as element()) {
  if ($name/tei:surname) then
    let $n := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]
    return normalize-space($n)
  else normalize-space($name)
};

(:~
 : Extract short name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function eltei:get-short-name ($author as element(tei:author)) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-short-name($name)
};

(:~
 : Extract short name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function eltei:get-short-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-short-name($name)
};

declare function local:build-sort-name ($name as element()) {
  (:
   : If there is a surname and it is not the first element in the name we
   : rearrange the name to put it first. Otherwise we just return the normalized
   : text as written in the document.
   :)
  if ($name/tei:surname and not($name/tei:*[1] = $name/tei:surname)) then
    let $start := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]

    return string-join(
      ($start, $start/(following-sibling::text()|following-sibling::*)), ""
    ) => normalize-space()
    || ", "
    || string-join(
      $start/(preceding-sibling::text()|preceding-sibling::*), ""
    ) => normalize-space()
  else normalize-space($name)
};

(:~
 : Extract name from author element that is suitable for sorting.
 :
 : @param $author author element
 : @return string
 :)
declare function eltei:get-sort-name ($author as element(tei:author) ) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-sort-name($name)
};

(:~
 : Extract name by language from author element that is suitable for sorting.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function eltei:get-sort-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-sort-name($name)
};

(:~
 : Retrieve array of refs from a 'ref' attribute.
 :
 : @param $ref A ref attribute
 :)
declare function eltei:get-refs($ref as node()) as array(xs:string*)* {
  let $ref-tokens := tokenize($ref)
  return array {
    (: FIXME: we are filtering invalid references here; these should
       rather be removed from the documents
     :)
    for $t in $ref-tokens
    let $parts := tokenize($t, ":")
    where not(matches($t, "^wikidata:[^Q]") or $parts[2] = ("missing", "unavailable"))
    return $t
  }
};

(:~
 : Retrieve author data from TEI.
 :
 : FIXME: Augmenting the author refs from our external authors.xml should be a
 : temporary solution until all corpora include the proper Wikidata ID as refs
 : in their documents.
 :
 : @param $tei TEI document
 :)
declare function eltei:get-authors($tei as node()) as map()* {
  for $author in $tei//tei:fileDesc/tei:titleStmt/tei:author[
    not(@role="illustrator")
  ]

  let $refs := if ($author/@ref) then eltei:get-refs($author/@ref) else array {}
  (:
    If there are refs, but no Wikidata IDs, we look for a match in our authors
    table
  :)
  let $lookup := if (count($refs?*) and not($refs?*[starts-with(., "wikidata:")])) then
    $eltei:authors//author[@ref = $refs?1][1]/@wikidata/string()
  else ()

  return map:merge((
    map {
      "name": tokenize(normalize-space($author), ' *\(')[1]
    },
    if (count($refs?*)) then
      map {
        "refs": array {
          $refs?*, if ($lookup) then "wikidata:" || $lookup else ()
        }
      }
    else ()
  ))
};

(:~
 : Extract year from a date element.
 :
 : @param $date date element
 :)
declare function eltei:get-year($date as element(tei:date)) as xs:string? {
  let $text := normalize-space($date)
  return if ($date/@when) then
    substring($date/@when, 1, 4)
  else if (matches($text, '^\d{4}$')) then
    $text
  else if (matches($text, '^\d{4}-\d{4}$')) then
    $text
  else analyze-string($text, '\d{4}')/fn:match[1]/text()
};

(:~
 : Extract sourceDesc entries from a TEI document.
 :
 : @param $tei TEI element
 :)
declare function eltei:get-sources($tei as element(tei:TEI)) as array(*) {
  let $sourceDesc := $tei/tei:teiHeader/tei:fileDesc/tei:sourceDesc

  return array {
    for $bibl in $sourceDesc/tei:bibl
    let $links := for $ref in $bibl/tei:ref
      let $target := $ref/@target/string()
      let $url := if (starts-with($target, 'http')) then
        $target
      else if (starts-with($target, 'textgrid:')) then
        'https://textgridrep.org/' || $target
      else if (starts-with($ref, 'http') and not($ref/@target)) then
        (: FIXME: the Polish corpus puts the URL into <ref> content :)
        normalize-space($ref)
      else ()
      return map:merge((
        map:entry("url", $url),
        if ($ref/text()) then map:entry("text", normalize-space($ref)) else ()
      ))

    return map:merge((
      map {
        "bibl": normalize-space($bibl)
      },
      if ($bibl/@type) then map:entry("type", string($bibl/@type)) else (),
      if ($bibl/tei:title) then
        map:entry("title", $bibl/tei:title[1]/normalize-space())
      else (),
      if ($bibl/tei:author) then
        map:entry("author", $bibl/tei:author[1]/normalize-space())
      else (),
      if ($bibl/tei:publisher) then
        map:entry("publisher", $bibl/tei:publisher[1]/normalize-space())
      else (),
      if ($bibl/tei:date) then
        map:entry("year", eltei:get-year($bibl/tei:date[1]))
      else (),
      if ($bibl/tei:pubPlace) then
        map:entry("placePublished", $bibl/tei:pubPlace[1]/normalize-space())
      else (),
      if (count($links)) then
        map:entry("links", array{$links})
      else ()
    ))
  }
};

(:~
 : Extract meta data for a text.
 :
 : @param $tei TEI element
 :)
declare function eltei:get-text-info($tei as element(tei:TEI)) as map()? {
  if ($tei) then
    let $id := eltei:get-eltec-id($tei)
    let $titles := eltei:get-titles($tei)
    let $authors := eltei:get-authors($tei)
    let $paths := elutil:filepaths($tei/base-uri())
    let $ref := $tei//tei:fileDesc/tei:titleStmt/tei:title/@ref
    let $sha := doc($paths?files?git)/git/sha/text()

    let $refs := if ($ref) then eltei:get-refs($ref) else array {}
    let $wikidata-id := if (not($refs?*[starts-with(., "wikidata")])) then
      $eltei:ids//text[@eltec = $id]/@wikidata
    else ()


    return map:merge((
      map {
        "id": $id,
        "name": $paths?textname,
        "corpus": $paths?corpusname,
        "title": $titles?main,
        "authors": array { for $author in $authors return $author },
        "sources": eltei:get-sources($tei)
      },
      if($ref) then map:entry("ref", $ref/string()) else (),
      if($sha) then map:entry("commit", $sha) else (),
      map:entry("refs", array {
        $refs?*, if ($wikidata-id) then "wikidata:" || $wikidata-id else ()
      }),
      map:entry("metrics", metrics:text($paths?corpusname, $paths?textname)),
      map:entry(
        "corpusUrl", $config:api-base || "/corpora/" || $paths?corpusname
      ),
      eltei:get-eltec-classification($tei),
      if (eltei:get-reference-year($tei))
        then map:entry("referenceYear", eltei:get-reference-year($tei))
        else ()
    ))
  else ()
};

(:~
 : Extract meta data for a text identified by corpus and text name.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function eltei:get-text-info(
  $corpusname as xs:string,
  $textname as xs:string
) as map()? {
  let $doc := elutil:get-doc($corpusname, $textname)
  return if ($doc) then eltei:get-text-info($doc//tei:TEI) else ()
};

(:~
 : Extract plain text from a TEI document.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function eltei:get-plain-text($tei as element(tei:TEI)) as xs:string? {
  string-join(
    $tei//tei:text//(tei:head|tei:p) ! normalize-space(),
    '&#xA;&#xA;'
  )
};

(:~
 : Extract plain text from a text identified by corpus and text name.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function eltei:get-plain-text(
  $corpusname as xs:string,
  $textname as xs:string
) as xs:string? {
  let $doc := elutil:get-doc($corpusname, $textname)
  return if ($doc) then eltei:get-plain-text($doc//tei:TEI) else ()
};

(:~
 : Extract meta data for all texts in corpus identified by corpusname.
 :
 : @param $corpusname
 :)
declare function eltei:get-corpus-text-info(
  $corpusname as xs:string
) as map()* {
  for $tei in elutil:get-corpus-docs($corpusname)
  return eltei:get-text-info($tei)
};

(:~
 : Extract corpus update timestamp from metrics.
 :
 : @param $corpusname
 :)
declare function eltei:get-corpus-update-time(
  $corpusname as xs:string
) as xs:dateTime* {
  let $col := collection(concat($config:corpora-root, "/", $corpusname))
  return max($col/metrics/xs:dateTime(@updated))
};

declare function local:to-markdown($input as element()) as item()* {
  for $child in $input/node()
  return
    if ($child instance of element())
    then (
      if (name($child) = 'ref')
      then "[" || $child/text() || "](" || $child/@target || ")"
      else if (name($child) = 'hi')
      then "**" || $child/text() || "**"
      else local:to-markdown($child)
    )
    else $child
};

declare function local:markdown($input as element()) as item()* {
  normalize-space(string-join(local:to-markdown($input), ''))
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function eltei:get-corpus-info(
  $corpus as element(tei:teiCorpus)*
) as map(*)* {
  let $header := $corpus/tei:teiHeader
  let $name := $header//tei:publicationStmt/tei:idno[not(@type)][1]/string()
  let $title := $header/tei:fileDesc/tei:titleStmt/tei:title[1]/string()
  let $acronym := $header/tei:fileDesc/tei:titleStmt/tei:title[@type="acronym"]/string()
  let $repo := $header//tei:publicationStmt/tei:idno[@type="repo"]/string()
  let $projectDesc := $header/tei:encodingDesc/tei:projectDesc
  let $licence := $header//tei:availability/tei:licence
  let $uri := $config:api-base || "/corpora/" || $name
  let $description := if ($projectDesc) then (
    let $paras := for $p in $projectDesc/tei:p return local:markdown($p)
    return string-join($paras, "&#10;&#10;")
  ) else ()
  let $git-file := $config:corpora-root || "/" || $name || "/git.xml"
  let $sha := doc($git-file)/git/sha/text()

  return if ($header) then (
    map:merge((
      map:entry("uri", $uri),
      map:entry("name", $name),
      map:entry("title", $title),
      map:entry("textsUrl", $uri || "/texts"),
      if ($acronym) then map:entry("acronym", $acronym) else (),
      if ($repo) then map:entry("repository", $repo) else (),
      if ($sha) then map:entry("commit", $sha) else (),
      if ($description) then map:entry("description", $description) else (),
      if ($licence)
        then map:entry("licence", normalize-space($licence)) else (),
      if ($licence/@target)
        then map:entry("licenceUrl", $licence/@target/string()) else (),
      map:entry("updated", eltei:get-corpus-update-time($name))
    ))
  ) else ()
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function eltei:get-corpus-info-by-name(
  $corpusname as xs:string
) as map(*)* {
  let $corpus := eltei:get-corpus($corpusname)
  return eltei:get-corpus-info($corpus)
};
