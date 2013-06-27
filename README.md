# taxrefine

TaxRefine: OpenRefine utilities for taxon name validation

## Tasks we need to be able to perform

We hope to meet the following uses:

#### Name matching and reconciliation
1. Name matching against another OpenRefine project (which might be a CSV, text file, or any other format supported by OpenRefine)
2. Name reconciliation against EOL (fuzzy matching) and GBIF Nub (non-fuzzy matching) via [Rod Page's reconciliation services](http://iphylo.blogspot.com/2012/02/using-google-refine-and-taxonomic.html).
3. Name reconciliation against [GBIF Checklist Bank](http://ecat-dev.gbif.org/) using [its API](http://dev.gbif.org/wiki/display/POR/Webservice+API).

#### Retrieve higher taxonomy
1. Retrieve higher taxonomy from ITIS using the [getFullHierarchyFromTSN](http://www.itis.gov/ws_hierApiDescription.html#getFullHierarchy) API call.
2. Retrieve higher taxonomy from GBIF.

#### Given a name, return a list of all known synonyms.
1. EOL provides this information through [its `pages` API call](http://eol.org/api/docs/pages).

**See something wrong?** [Please let us know](https://github.com/gaurav/taxrefine/issues)!
