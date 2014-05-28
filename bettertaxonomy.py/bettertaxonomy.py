#!/usr/bin/env python

import argparse
import datetime
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
cmdline.add_argument('-internal',
    nargs='?',
    type=str,
    help='Internal list of name corrections (must be a CSV file)')

args = cmdline.parse_args()

# Load the entire internal list, if it exists.
internal_corrections = dict()
ic_fieldnames = None
if args.internal:
    reader = csv.DictReader(open(args.internal, "r"), dialect=csv.excel)
    ic_fieldnames = reader.fieldnames
    row_index = 0
    for row in reader:
        row_index+=1
        scname = row['scientificName']
        if scname == None:
            raise RuntimeError('No scientific name on row {0:d}'.format(row_index))
        elif scname in internal_corrections:
            raise RuntimeError('Duplicate scientificName detected: "{0:d}"'.format(scname))
        else:
            internal_corrections[scname] = row

# Our input should be a CSV or text delimited.
timestamp = datetime.datetime.now().strftime("%x")
unmatched_names = []
for input in args.input:
    try:
        dialect = csv.Sniffer().sniff(input.read(1024), delimiters="\t,;|")
        input.seek(0)
        reader = csv.DictReader(input, dialect=csv.excel)
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

    header.insert(header.index(args.fieldname) + 1, 'matched_scname')
    header.insert(header.index(args.fieldname) + 2, 'matched_acname')
    header.insert(header.index(args.fieldname) + 3, 'matched_url')
    header.insert(header.index(args.fieldname) + 4, 'matched_source')
   
    output = csv.DictWriter(sys.stdout, header, dialect)
    output.writeheader()

    for row in reader:
        name = row[args.fieldname]

        matched_scname = None
        matched_url = None
        matched_source = None

        if name in internal_corrections:
            matched_scname = internal_corrections[name].get('correctName')
            matched_acname = internal_corrections[name].get('correctAcceptedName')
            matched_url = "//internal"
            matched_source = "internal (as of " + timestamp + ")"
        else:
            matches = gbif_api.get_matches_from_taxrefine(name)
            if len(matches) > 0:
                matched_scname = matches[0]['name']
                matched_url = gbif_api.get_url_for_id(matches[0]['id'])
                matched_source = "TaxRefine/GBIF API queried on " + timestamp
            else: 
                unmatched_names.append(name)

        row['matched_scname'] = matched_scname
        row['matched_url'] = matched_url
        row['matched_source'] = matched_source

        output.writerow(row)

if args.internal and len(unmatched_names) > 0:
    internal_file = open(args.internal, mode="a")
    writer = csv.DictWriter(internal_file, ic_fieldnames, dialect=csv.excel)
    
    dict_row = dict()
    for colname in ic_fieldnames:
        dict_row[colname] = None

    for name in unmatched_names:
        dict_row['scientificName'] = name
        writer.writerow(dict_row)

    internal_file.close()
