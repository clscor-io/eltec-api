xquery version "3.1";

(:~
 : Module for calculating and updating corpus metrics.
 :)
module namespace metrics = "http://eltec.clscor.io/ns/exist/metrics";

import module namespace config = "http://eltec.clscor.io/ns/exist/config" at "config.xqm";
import module namespace elutil = "http://eltec.clscor.io/ns/exist/util" at "util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Separator for word count tokenization :)
declare variable $metrics:separator := "\W+";

(:~
 : Count words in tei:text of a TEI document
 :
 : @param $tei TEI document
:)
declare function metrics:word-count($tei as element(tei:TEI)) {
  count(tokenize($tei//tei:text[1], $metrics:separator))
};

(:~
 : Calculate metrics for single text
 :
 : @param $url URL of the TEI document
:)
declare function metrics:calculate($url as xs:string) {
  let $tei := doc($url)/tei:TEI
  let $word-count := metrics:word-count($tei)
  return
  <metrics updated="{current-dateTime()}">
    <words>{$word-count}</words>
  </metrics>
};

(:~
 : Update metrics for single text
 :
 : @param $url URL of the TEI document
:)
declare function metrics:update($url as xs:string) {
  let $metrics := metrics:calculate($url)
  let $paths := elutil:filepaths($url)
  let $collection := $paths?collections?text
  return (
    util:log-system-out('Metrics update: ' || $paths?files?metrics),
    xmldb:store($collection, "metrics.xml", $metrics)
  )
};

(:~
 : Update metrics for all texts in the database
:)
declare function metrics:update() as xs:string* {
  let $l := util:log-system-out("Updating metrics files")
  for $tei in collection($config:corpora-root)//tei:TEI
  let $url := $tei/base-uri()
  return metrics:update($url)
};

declare function metrics:corpus ($corpus as xs:string) {
  let $col := collection(concat($config:corpora-root, "/", $corpus))
  return map {
    "numOfTexts": count($col/tei:TEI),
    "numOfAuthors": count(distinct-values($col//tei:titleStmt//tei:author)),
    "numOfParagraphs": count($col//tei:body//tei:p),
    "numOfWords": sum($col//words)
  }
};

declare function metrics:text (
  $corpusname as xs:string,
  $textname as xs:string
) {
  let $doc := elutil:get-doc($corpusname, $textname)
  let $paths := elutil:filepaths($corpusname, $textname)
  let $metrics := doc($paths?files?metrics)
  return map {
    "numOfChapters": count($doc/tei:TEI//tei:text//tei:div[@type = "chapter"]),
    "numOfParagraphs": count($doc/tei:TEI//tei:body//tei:p),
    "numOfWords": sum($metrics//words)
  }
};
