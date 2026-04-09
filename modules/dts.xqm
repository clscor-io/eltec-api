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
module namespace dts = "http://eltec.clscor.io/ns/exist/dts";

import module namespace config = "http://eltec.clscor.io/ns/exist/config"
  at "config.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: DTS v1.0 constants :)
declare variable $dts:spec-version := "1.0";
declare variable $dts:jsonld-context := "https://dtsapi.org/context/v1.0.json";
declare variable $dts:ns := "https://dtsapi.org/v1.0#";

(: Base URLs for DTS endpoints :)
declare variable $dts:api-base := $config:api-base || "/dts";
declare variable $dts:collection-base := $dts:api-base || "/collection";
declare variable $dts:navigation-base := $dts:api-base || "/navigation";
declare variable $dts:document-base := $dts:api-base || "/document";

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
function dts:entry-point()
as map() {
  map {
    "@context": $dts:jsonld-context,
    "@id": $dts:api-base,
    "@type": "EntryPoint",
    "dtsVersion": $dts:spec-version,
    "collection": $dts:collection-base || "/{?id,page,nav}",
    "navigation": $dts:navigation-base || "/{?resource,ref,start,end,down,tree,page}",
    "document": $dts:document-base || "/{?resource,ref,start,end,tree,mediaType}"
  }
};
