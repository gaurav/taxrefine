#!/usr/bin/env python

import argparse
import gbif_api
import csv
import sys

# Read the command line.
cmdline = argparse.ArgumentParser(description = 'Match species names')
cmdline.add_argument('input', 
    nargs='*', 
    type=argparse.FileType('r'),
    help='A CSV or plain text file containing species names',
    default = [sys.stdin])
cmdline.add_argument('-fieldname',
    type=str,
    help='The field containing scientific names to match',
    default = 'scientificName')

args = cmdline.parse_args()

# Our input should be a CSV or text delimited.
for input in args.input:
    try:
        dialect = csv.Sniffer().sniff(input.read(1024), delimiters="\t,;|")
        input.seek(0)
        reader = csv.DictReader(input, dialect)
        header = reader.fieldnames()
    except csv.Error as e:
        # let's assume it's a plain-text file with a header
        # which is basically excel_tab, isn't it.
        input.seek(0)
        header = [input.readline().rstrip()]
        dialect = csv.excel_tab
        reader = csv.DictReader(input, dialect=dialect, fieldnames=header)

 
    if header.count(args.fieldname) == 0:
        print "Error: could not find field '{0:s}' in file".format(args.fieldname)
        exit(1)

    header.insert(header.index(args.fieldname) + 1, 'gbif_id')
    header.insert(header.index(args.fieldname) + 2, 'gbif_score')
   
    output = csv.DictWriter(sys.stdout, header, dialect)
    output.writeheader()

    for row in reader:
        name = row[args.fieldname]
        matches = gbif_api.get_matches_from_taxrefine(name)
        if len(matches) == 0: 
            row['gbif_id'] = "null"
            row['gbif_score'] = 0
        else:
            row['gbif_id'] = matches[0]['id']
            row['gbif_score'] = matches[0]['score']
        output.writerow(row)
# 
