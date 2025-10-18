xquery version "3.1";

module namespace ect = "http://eltec.clscor.io/ns/exist/trigger";

import module namespace elutil = "http://eltec.clscor.io/ns/exist/util" at "util.xqm";
import module namespace metrics = "http://eltec.clscor.io/ns/exist/metrics" at "metrics.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";


declare function trigger:after-create-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then
    (
      util:log-system-out("running CREATION TRIGGER for " || $url),
      metrics:update($url)
    )
  else ()
};

declare function trigger:after-update-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then
    (
      util:log-system-out("running UPDATE TRIGGER for " || $url),
      metrics:update($url)
    )
  else ()
};

declare function trigger:before-delete-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml")) then
    util:log-system-out("about to DELETE " || $url)
  else ()
};
