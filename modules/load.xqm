xquery version "3.1";

(:~
 : Module providing function to load files from zip archives.
 :)
module namespace load = "http://eltec.clscor.io/ns/exist/load";

import module namespace config = "http://eltec.clscor.io/ns/exist/config" at "config.xqm";
import module namespace eltei = "http://eltec.clscor.io/ns/exist/tei" at "tei.xqm";

declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: FIXME :)
declare function local:entry-data(
  $path as xs:anyURI,
  $type as xs:string,
  $data as item()?,
  $param as item()*
) as item()? {
  if($data) then
    let $collection := $param[1]
    let $name := tokenize($path, "/")[last()]
    let $log := util:log-system-out($collection || " / " || $name)
    let $res := xmldb:store($collection, xmldb:encode($name), $data)
    return $res
  else
    ()
};

declare function local:entry-filter(
  $path as xs:anyURI,
  $type as xs:string,
  $param as item()*
) as xs:boolean {
  (: filter paths using only corpus.xml or files in the "tei" subdirectory :)
  if ($type eq "resource" and (
    contains($path, "/tei/") or contains($path, "corpus.xml")
  ))
  then
    true()
  else
    false()
};

(: FIXME: adopt github functions from dracor-api  :)
(:~
 : Load corpus from ZIP archive
 :
 : @param $corpus The <corpus> element providing corpus name and archive URL
 : @return List of created collections and files
:)
declare function load:load-corpus($corpus as element(tei:teiCorpus))
as xs:string* {
  let $info := eltei:get-corpus-info($corpus)
  let $name := $info?name

  let $corpus-collection := $config:corpora-root || "/" || $name

  let $archive :=
    if ($info?archive) then
      $info?archive
    else if (starts-with($info?repository, "https://github.com")) then
      $info?repository || "/archive/main.zip"
    else ()

  return
    if (not($archive)) then (
      util:log-system-out("cannot determine archive URL")
    )
    else
      let $log := util:log-system-out("loading " || $archive)
      let $request := <hc:request method="get" href="{ $archive }" />
      (: TODO handle request failure :)
      let $response := hc:send-request($request)
      return
        if ($response[1]/@status = "200") then
          let $body := $response[2]
          let $zip := xs:base64Binary($body)
          return (
            (: remove TEI documents :)
            for $tei in collection($data-collection)/tei:TEI
            let $resource := tokenize($tei/base-uri(), '/')[last()]
            return (
              util:log-system-out("removing " || $resource),
              xmldb:remove($data-collection, $resource)
            ),
            (: load files from ZIP archive :)
            compression:unzip(
              $zip,
              util:function(xs:QName("local:entry-filter"), 3),
              (),
              util:function(xs:QName("local:entry-data"), 4),
              (: FIXME maybe :)
              ($corpora-collection)
            )
          )
        else (
          util:log("warn", ("cannot load archive ", $archive)),
          util:log("info", $response)
        )
};
