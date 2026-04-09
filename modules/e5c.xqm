xquery version "3.1";

(:~
 : E5C Conformance Score
 :
 : Implements the ELTeC Corpus Composition Conformance (E5C) scoring system.
 : Ported from summarize.xsl in the eltec-scripts repository.
 :
 : The E5C score is a weighted composite of 8 sub-scores measuring how well
 : a corpus meets the ELTeC balance criteria.
 :)
module namespace e5c = "http://eltec.clscor.io/ns/exist/e5c";

import module namespace config = "http://eltec.clscor.io/ns/exist/config"
  at "config.xqm";
import module namespace metrics = "http://eltec.clscor.io/ns/exist/metrics"
  at "metrics.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace eltec = "http://distantreading.net/eltec/ns";

(:~
 : Text count score (weight 3x).
 : Linear scale: 0 for <10 texts, 10 for 100+ texts.
 :)
declare function e5c:text-score($textCount as xs:integer) as xs:integer {
  if ($textCount < 10) then 0
  else if ($textCount < 20) then 1
  else if ($textCount < 30) then 2
  else if ($textCount < 40) then 3
  else if ($textCount < 50) then 4
  else if ($textCount < 60) then 5
  else if ($textCount < 70) then 6
  else if ($textCount < 80) then 7
  else if ($textCount < 90) then 8
  else if ($textCount < 100) then 9
  else 10
};

(:~
 : Female author score (weight 2x).
 : Optimal: 40-60% female. Penalizes both under- and over-representation.
 :)
declare function e5c:female-score($femalePerc as xs:double) as xs:double {
  if ($femalePerc < 10) then $femalePerc
  else if ($femalePerc < 40) then 10
  else if ($femalePerc < 60) then 11
  else if ($femalePerc < 80) then 6
  else if ($femalePerc < 90) then 3
  else 0
};

(:~
 : Reprint score (weight 2x).
 : Based on percentage of texts with low reprint count.
 : Optimal: 30-60%.
 :)
declare function e5c:reprint-score($reprintPerc as xs:double) as xs:integer {
  if ($reprintPerc = 0) then 0
  else if ($reprintPerc < 5) then 1
  else if ($reprintPerc < 9) then 2
  else if ($reprintPerc < 12) then 3
  else if ($reprintPerc < 15) then 4
  else if ($reprintPerc < 18) then 5
  else if ($reprintPerc < 21) then 6
  else if ($reprintPerc < 24) then 7
  else if ($reprintPerc < 27) then 8
  else if ($reprintPerc < 30) then 9
  else if ($reprintPerc < 40) then 10
  else if ($reprintPerc < 60) then 11
  else if ($reprintPerc < 71) then 10
  else if ($reprintPerc < 81) then 6
  else if ($reprintPerc < 91) then 3
  else 0
};

(:~
 : Short text score (weight 1x).
 : Based on percentage of texts < 50k words. Optimal: 20-37%.
 :)
declare function e5c:short-score($shortPerc as xs:double) as xs:integer {
  if ($shortPerc = 0) then 0
  else if ($shortPerc < 4) then 1
  else if ($shortPerc < 6) then 2
  else if ($shortPerc < 8) then 3
  else if ($shortPerc < 10) then 4
  else if ($shortPerc < 12) then 5
  else if ($shortPerc < 14) then 6
  else if ($shortPerc < 16) then 7
  else if ($shortPerc < 18) then 8
  else if ($shortPerc < 20) then 9
  else if ($shortPerc < 30) then 10
  else if ($shortPerc < 37) then 11
  else if ($shortPerc < 61) then 10
  else if ($shortPerc < 71) then 9
  else if ($shortPerc < 81) then 8
  else if ($shortPerc < 91) then 5
  else 2
};

(:~
 : Long text score (weight 1x).
 : Based on percentage of texts > 100k words. Same curve as short score.
 :)
declare function e5c:long-score($longPerc as xs:double) as xs:integer {
  if ($longPerc = 0) then 0
  else if ($longPerc < 4) then 1
  else if ($longPerc < 6) then 2
  else if ($longPerc < 8) then 3
  else if ($longPerc < 10) then 4
  else if ($longPerc < 12) then 5
  else if ($longPerc < 14) then 6
  else if ($longPerc < 16) then 7
  else if ($longPerc < 18) then 8
  else if ($longPerc < 20) then 9
  else if ($longPerc < 30) then 10
  else if ($longPerc < 37) then 11
  else if ($longPerc < 61) then 10
  else if ($longPerc < 71) then 9
  else if ($longPerc < 81) then 8
  else if ($longPerc < 91) then 5
  else 2
};

(:~
 : Triple-text author score (weight 1x).
 : Based on percentage of texts by authors contributing 3+ texts.
 : Optimal: 27-34%.
 :)
declare function e5c:triple-score($triplePerc as xs:double) as xs:integer {
  if ($triplePerc < 3) then 0
  else if ($triplePerc < 6) then 2
  else if ($triplePerc < 9) then 3
  else if ($triplePerc < 12) then 4
  else if ($triplePerc < 15) then 5
  else if ($triplePerc < 18) then 6
  else if ($triplePerc < 21) then 7
  else if ($triplePerc < 24) then 8
  else if ($triplePerc < 27) then 9
  else if ($triplePerc < 34) then 10
  else if ($triplePerc < 37) then 9
  else if ($triplePerc < 40) then 8
  else if ($triplePerc < 55) then 7
  else if ($triplePerc < 70) then 6
  else if ($triplePerc < 85) then 3
  else 0
};

(:~
 : Single-text author score (weight 1x).
 : Based on percentage of texts by authors contributing exactly 1 text.
 : Optimal: 60-74%.
 :)
declare function e5c:single-score($singlePerc as xs:double) as xs:integer {
  if ($singlePerc < 10) then 0
  else if ($singlePerc < 20) then 1
  else if ($singlePerc < 30) then 2
  else if ($singlePerc < 35) then 3
  else if ($singlePerc < 40) then 4
  else if ($singlePerc < 45) then 5
  else if ($singlePerc < 50) then 6
  else if ($singlePerc < 55) then 7
  else if ($singlePerc < 60) then 8
  else if ($singlePerc < 67) then 9
  else if ($singlePerc < 74) then 10
  else if ($singlePerc < 77) then 9
  else if ($singlePerc < 80) then 8
  else if ($singlePerc < 85) then 7
  else if ($singlePerc < 90) then 6
  else if ($singlePerc < 95) then 3
  else 0
};

(:~
 : Time range score (weight 2x).
 : Based on spread between most and least populated time slots.
 : Lower spread = more even distribution = higher score.
 :)
declare function e5c:range-score($rangePerc as xs:double) as xs:integer {
  if ($rangePerc < 10) then 10
  else if ($rangePerc < 15) then 9
  else if ($rangePerc < 20) then 8
  else if ($rangePerc < 25) then 7
  else if ($rangePerc < 30) then 6
  else if ($rangePerc < 40) then 5
  else if ($rangePerc < 50) then 4
  else if ($rangePerc < 60) then 3
  else if ($rangePerc < 70) then 2
  else if ($rangePerc < 80) then 1
  else 0
};

(:~
 : Calculate E5C conformance score for a corpus.
 :
 : @param $corpus Corpus name
 : @return map with e5c score, subscores, and corpus class
 :)
declare function e5c:calculate($corpus as xs:string) as map() {
  let $col := collection(concat($config:corpora-root, "/", $corpus))
  let $balance := metrics:corpus-balance($corpus)

  let $textCount := count($col/tei:TEI)

  (: Gender :)
  let $femalePerc := $balance?gender?F div $textCount * 100

  (: Reprint — percentage of low reprints :)
  let $reprintPerc := $balance?reprintCount?low div $textCount * 100

  (: Size :)
  let $shortPerc := $balance?size?short div $textCount * 100
  let $longPerc := $balance?size?long div $textCount * 100

  (: Time range — spread between max and min slot counts :)
  let $slots := ($balance?timeSlot?T1, $balance?timeSlot?T2,
                 $balance?timeSlot?T3, $balance?timeSlot?T4)
  let $rangeCount := max($slots) - min($slots)
  let $rangePerc := $rangeCount div $textCount * 100

  (: Author diversity :)
  (: triplePerc = percentage of TEXTS by 3+ text authors :)
  let $tripleAuthors := $balance?authorDiversity?tripleTextAuthors
  (: count texts by these authors — each triple author contributes 3+ texts :)
  let $authors := $col//tei:titleStmt/tei:author[1]
  let $tripleTextCount := sum(
    for $a in distinct-values($authors ! normalize-space(.))
    let $count := count($authors[normalize-space(.) = $a])
    where $count >= 3
    return $count
  )
  let $triplePerc := $tripleTextCount div $textCount * 100

  (: singlePerc = percentage of TEXTS by single-text authors :)
  let $singleTextCount := $balance?authorDiversity?singleTextAuthors
  let $singlePerc := $singleTextCount div $textCount * 100

  (: Compute sub-scores :)
  let $ts := e5c:text-score($textCount)
  let $fs := e5c:female-score($femalePerc)
  let $rs := e5c:reprint-score($reprintPerc)
  let $ss := e5c:short-score($shortPerc)
  let $ls := e5c:long-score($longPerc)
  let $trs := e5c:triple-score($triplePerc)
  let $sns := e5c:single-score($singlePerc)
  let $rgs := e5c:range-score($rangePerc)

  (: Composite formula: weighted sum / 13 * 10 :)
  let $e5cScore := ($ts * 3 + $fs * 2 + $sns + $trs + $ss + $ls
    + $rgs * 2 + $rs * 2) div 13 * 10

  let $class :=
    if (contains($corpus, '-ext')) then "extended"
    else if ($textCount >= 100) then "core"
    else if ($e5cScore > 1) then "plus"
    else "extended"

  return map {
    "e5c": round-half-to-even($e5cScore, 2),
    "class": $class,
    "subscores": map {
      "text": $ts,
      "female": $fs,
      "single": $sns,
      "triple": $trs,
      "short": $ss,
      "long": $ls,
      "range": $rgs,
      "reprint": $rs
    }
  }
};
