xquery version "3.1";

(:~
 : Module providing utility functions for ELTeC API.
 :)
module namespace elutil = "http://eltec.clscor.io/ns/exist/util";

import module namespace config = "http://eltec.clscor.io/ns/exist/config" at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace json = "http://www.w3.org/2013/XSL/json";

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $url DB URL to text TEI document
 : @return map()
 :)
declare function elutil:filepaths ($url as xs:string) as map() {
  let $segments := tokenize($url, "/")
  let $corpusname := $segments[last() - 2]
  let $textname := $segments[last() - 1]
  let $filename := $segments[last()]
  return elutil:filepaths($corpusname, $textname, $filename)
};

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $corpusname
 : @param $textname
 : @return map()
 :)
declare function elutil:filepaths (
  $corpusname as xs:string,
  $textname as xs:string
) as map() {
  elutil:filepaths($corpusname, $textname, "tei.xml")
};

(:~
 : Provide map of files and paths related to a text.
 :
 : @param $corpusname
 : @param $textname
 : @param $filename
 : @return map()
 :)
declare function elutil:filepaths (
  $corpusname as xs:string,
  $textname as xs:string,
  $filename as xs:string
) as map() {
  let $textpath := $config:corpora-root || "/" || $corpusname || "/" || $textname
  let $url := $textpath || "/" || $filename
  let $uri :=
    $config:api-base || "/corpora/" || $corpusname || "/texts/" || $textname
  return map {
    "uri": $uri,
    "url": $url,
    "filename": $filename,
    "textname": $textname,
    "corpusname": $corpusname,
    "collections": map {
      "corpus": $config:corpora-root || "/" || $corpusname,
      "text": $textpath
    },
    "files": map {
      "tei": $textpath || "/tei.xml",
      "metrics": $textpath || "/metrics.xml",
      "git": $textpath || "/git.xml"
    }
  }
};

(:~
 : Return document for an individual text.
 :
 : @param $corpusname
 : @param $textname
 : @param $root Path to root directory
 :)
declare function elutil:get-doc(
  $corpusname as xs:string,
  $textname as xs:string,
  $root as xs:string
) as node()* {
  doc($root || "/" || $corpusname || "/" || $textname || "/tei.xml")
};


(:~
 : Return TEI document for an individual text.
 :
 : @param $corpusname
 : @param $textname
 :)
declare function elutil:get-doc(
  $corpusname as xs:string,
  $textname as xs:string
) as node()* {
  let $paths := elutil:filepaths($corpusname, $textname)
  return doc($paths?files?tei)
};

(:~
 : Return documents in a corpus.
 :
 : @param $corpusname
 :)
declare function elutil:get-corpus-docs(
  $corpusname as xs:string
) as node()* {
  let $collection := $config:corpora-root || "/" || $corpusname
  let $col := collection($collection)
  return $col//tei:TEI
};
