# taxrefine

OpenRefine utilities for taxon name validation.

## What TaxRefine does

TaxRefine summarizes search results from the GBIF API to try to pick the best supported interpretation of a 
particular name from across the hundreds of checklists assembled by GBIF.

TaxRefine is a wrapper around [GBIF's Search Names](http://www.gbif.org/developer/species#searching).
It searches for names on the GBIF Nub using the `/species/match` API query; if it finds no matches,
it uses the `/species/search` to look for the exact name on other checklists.

Once it finds a match, it finds the list of related names on GBIF (using the 
`/species/{int}/related` API query). It then goes through all these related names and
groups them on the basis of four criteria:

1. Scientific name
2. Accepted name
3. Authority
4. Kingdom

It returns them sorted by the number of checklists matched in each group. For each group, 
it also generates a summary of possible values (this might still be a little buggy).

## Tasks we might want to do

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
