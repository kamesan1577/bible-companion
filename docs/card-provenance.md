# Initial source-card provenance

Verified **2026-10-13 (UTC)**. Fixture: `packages/core/fixtures/source-cards.json`.

This is a deliberately small, editorially reviewed starter set: **12 episode-scoped person cards, 3 place cards, and 1 artwork card**. It is not exhaustive historical or theological coverage. Japanese summaries are original application commentary, not JCB text or a new Bible translation. None was generated with a paid model call. Source verification establishes support for each bounded description; it does not claim external scholarly peer review.

## Text and identification policy

- The primary literary source is the public-domain World English Bible (WEB), `engwebp`, with direct verse anchors. Its [rights notice](https://ebible.org/engwebp/copyright.htm) explicitly permits copying and redistribution. We do not label our Japanese prose as WEB or JCB.
- Bible-based cards describe what the text says. They do not independently verify every narrated event as modern historical fact.
- A source's `license: citation-only` means its facts are cited and summarized originally. It does **not** authorize copying source prose or images. This is particularly important for museum object descriptions.
- People are scoped to a specific textual appearance. Sosthenes is not merged with a person from another book merely because the names match. The unnamed group in Acts 19 is not identified with the twelve apostles or presumed to be Apollos's students.
- Paul, Aquila, Priscilla, and Apollos have episode-scoped cards where adding later information to their first appearance would otherwise reveal unread events. The end boundary covers every displayed field, including the title and identity note.
- No coordinates are included: neither inferred geocodes nor modern city-center approximations are represented as a verified ancient location. `coordinates: null` is intentional. Geographic identification is confirmed at site level; an excavated point or building is not claimed.

## Claim audit and minimum reveal boundaries

The following bounds apply to the complete summary and details. The schema has one bound per card, so cards are separated when a later episode requires a higher bound. Bounds use the same book (`ACT`) and ordinary chapter/verse order, including cross-chapter imports.

| Card ID | Supported assertion | Primary evidence | Minimum complete-card reveal |
|---|---|---|---|
| person-paul-act18-arrival | Paul reaches Corinth from Athens | [Acts 18:1](https://ebible.org/engwebp/ACT18.htm#V1) | Acts 18:1 |
| person-aquila-act18-introduction | Aquila, Pontus, Priscilla, Italy, Claudius's expulsion as narrated background | [Acts 18:2](https://ebible.org/engwebp/ACT18.htm#V2) | Acts 18:2 |
| person-priscilla-act18-introduction | Priscilla is Aquila's wife and came with him from Italy | [Acts 18:2](https://ebible.org/engwebp/ACT18.htm#V2) | Acts 18:2 |
| person-paul-act18-work | Same trade, shared home/work, tent-making; no process specified | [Acts 18:2–3](https://ebible.org/engwebp/ACT18.htm#V2) | Acts 18:3 |
| person-crispus-act18 | Synagogue leader, belief with household | [Acts 18:8](https://ebible.org/engwebp/ACT18.htm#V8) | Acts 18:8 |
| person-gallio-act18 | Proconsul of Achaia, refusal and dismissal; inner motive unspecified | [Acts 18:12–16](https://ebible.org/engwebp/ACT18.htm#V12) | Acts 18:16 |
| person-sosthenes-act18 | Synagogue leader assaulted before tribunal; no cross-book identity assertion | [Acts 18:17](https://ebible.org/engwebp/ACT18.htm#V17) | Acts 18:17 |
| person-apollos-act18-introduction | Alexandrian Jewish speaker, knowledge of Scripture, arrival in Ephesus | [Acts 18:24](https://ebible.org/engwebp/ACT18.htm#V24) | Acts 18:24 |
| person-apollos-act18-learning | John's baptism and more exact teaching from Priscilla and Aquila; instruction's full content unstated | [Acts 18:25–26](https://ebible.org/engwebp/ACT18.htm#V25) | Acts 18:26 |
| person-apollos-act18-achaia | Letter of welcome, move into Achaia, assistance and Scripture argument | [Acts 18:27–28](https://ebible.org/engwebp/ACT18.htm#V27) | Acts 18:28 |
| person-paul-act19-ephesus | Apollos in Corinth, Paul through inland country to Ephesus, meeting disciples | [Acts 19:1](https://ebible.org/engwebp/ACT19.htm#V1) | Acts 19:1 |
| person-disciples-act19 | John's baptism, baptism in Jesus's name, laying on hands, Spirit/languages/prophecy as narrated, about twelve | [Acts 19:2–7](https://ebible.org/engwebp/ACT19.htm#V2) | Acts 19:7 |
| place-corinth | Land corridor between central Greece and Peloponnese; Paul arrives | [ASCSA Corinth](https://www.ascsa.edu.gr/publications/browse-by-series/corinth); Acts 18:1 | Acts 18:1 |
| place-cenchreae | Corinth's eastern harbor; shaving associated with vow, without guessing the vow's content | [ASCSA Hesperia 76.1, 143–181](https://www.ascsa.edu.gr/publications/hesperia/article/76/1/143-181); [excavation report](https://www.ascsa.edu.gr/index.php/news/newsDetails/report-on-kenchreai-2012); Acts 18:18 | Acts 18:18 |
| place-ephesus | Western Turkey; ancient seafront and changing harbor/channel from silting | [Austrian Archaeological Institute](https://www.oeaw.ac.at/en/oeai/media/news-archive/news-detail/130-jahre-oesterreichische-grabung-ephesos), opening and image-gallery caption | Acts 18:19 |
| art-tintoretto-conversion-paul | Tintoretto, c.1544, NGA collection and accession, explicit Acts 9:3–7 connection, dramatic artistic treatment | [NGA object 46142](https://www.nga.gov/artworks/46142-conversion-saint-paul); [Acts 9:3–7](https://ebible.org/engwebp/ACT09.htm#V3) | Acts 9:7 |

ASCSA's own indexed primary pages were readable in the research search results; direct reopens intermittently timed out or returned 502. The cited archaeology facts were verified in that first-party text, not inferred from a generic search headline. The Austrian source is the excavation institution itself. Dates of archaeological publication are not dates of the biblical events.

## Artwork rights and image scope

The NGA object page explicitly marks **this object's media** free and in the public domain. Its linked [Open Access policy](https://www.nga.gov/terms-and-notices) releases eligible images under **CC0**, for commercial and noncommercial use. The object's direct image link, rather than a generic museum-wide assumption, establishes eligibility. No new terms were accepted and no account was created.

Artwork identity: Jacopo Tintoretto, *The Conversion of Saint Paul*, c.1544; oil on canvas; National Gallery of Art, Washington; Samuel H. Kress Collection; accession **1961.9.43**. The fixture uses the official 800-pixel IIIF image link emitted by that object's page. It does not hotlink an image from a search engine or unrelated website. The exact image URL was fetched on 2026-10-13: HTTP 200, `image/jpeg`, 146,720 bytes, 800 × 514 pixels. The downloaded preview was visually inspected and matches this object. SHA-256: `adbbf3350c84b2045109c2203426163461e52a27a196f9b98054aba1a921091b`. Client rendering and future availability remain separate checks.

Courtesy credit included in the fixture: “Courtesy National Gallery of Art, Washington.” Artist, title, date, collection, and accession are also supplied. No endorsement is implied. The museum notes that it cannot warrant third-party rights in every jurisdiction. The object-page prose itself is not covered by the image's CC0 release; our brief Japanese description is original.

The painting belongs to **Acts 9:3–7**, not Acts 18. Its relationship is `direct` only for that passage. The fact that Paul also appears in Acts 18 must not make this artwork a direct match for Acts 18. The painting is a sixteenth-century interpretation, not a contemporaneous documentary image. No assertion that Saul traveled on a horse is made from the Bible text.

The Ephesus photographs have a narrower permission for media coverage with credit; they are **not bundled or linked as application media**. ASCSA photographs have not received individual reuse clearance and are also excluded. No generative image is presented as archaeology or historical evidence.

## Operational safeguards

- Require approved, reviewed, active card records and the whole-card reveal bound before returning a card; title, provenance and media should not leak excluded cards.
- Select direct cards only through an intersecting `passages` entry. Do not select artwork by shared person name alone.
- Deactivate/revoke individual cards if evidence or rights change and include card changes in the live content manifest/cache version.
- A missing image must leave a readable card with an official object-page link. Media is an optional enhancement, not evidence of completed download or successful client rendering.
- The startup corpus needs future breadth and expert review; an empty category outside these reviewed passages should honestly report missing reviewed material.

## Bounded question grounding

Approved server-curated card summaries can also ground questions as `commentary`, separately from `scripture`. The API projects at most eight relevant cards into the shared 64-source context limit. It uses the original Japanese summary only, never an external article body, image pixels, coordinate database dump or user-supplied claim. The card's existing whole-card reveal endpoint, passage applicability, active/approved rights, editorial review and immutable ID/version are checked before the summary enters a prompt.

Citations retain `sourceKind: commentary` and a `reviewed-material-summary` provenance record with every reference, publisher, rights label, license URL and attribution. The summary/evidence quote identifies the reviewed text used; matching that quote does not independently prove the truth of every external claim. Artwork summaries are labeled inference because an artistic depiction is interpretation, not contemporary documentary evidence. Experimental generated paraphrases retain the semantic-grounding warning.

The `material:` source namespace is reserved. Correcting semantic card content requires a new version, including after deletion/reinsertion. Revocation changes the global source-policy epoch, blocks in-flight publication, and hides affected historical assistant bodies while preserving user questions. Private answer caches and comparison plans include source/prompt policy identity. The reading overview's existing public-domain offline grant does not expand to these commentary summaries; native storage also rejects material provenance there.

The Cenchreae question acceptance case uses a fixture provider to cite the approved eastern-harbor summary and its WEB/ASCSA/Pleiades references. It verifies provenance and revocation behavior, not actual model quality. Unreviewed, denied, future-bound and forged-namespace cards are excluded in tests.
