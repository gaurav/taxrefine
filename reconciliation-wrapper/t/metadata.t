#!/usr/bin/perl -w

use v5.010;

use strict;
use warnings;

our $AGREW_URL = $ENV{'AGREW_URL'} // 'http://localhost:3000/reconcile';

use Test::WWW::Mechanize;
use JSON;
use Try::Tiny;

use Test::More tests => 1;

my $mech = Test::WWW::Mechanize->new;

=head1 NAME

metadata.t -- Tests the metadata for the reconciliation service.

=head1 TESTS FOR

=head2 Service metadata is accessible.

Checks that the $AGREW_URL is accessible, and returns parseable 'application/json' content.

=cut

subtest "Server responds correctly to a simple request" => sub {
    plan tests => 6;

    # Make the request
    my $response = $mech->get($AGREW_URL);
    ok($response->is_success, "Successfully accessed '$AGREW_URL'");
    is($response->content_type, 'application/json', "Content-type is 'application/json'");

    # Parse the returned JSON.
    my $content = $response->decoded_content;
    my $json_object;
    try {
        $json_object = decode_json $content;
    } catch {
        fail("Could not parse returned JSON: " . $_);
        return;
    };
    
    pass "Returned JSON parsed successfully.";

    # Check if the returned JSON has the required fields.
    isnt($json_object->{'name'}, "", 
        "Checking for non-blank 'name' in service metadata");
    isnt($json_object->{'identifierSpace'}, "", 
        "Checking for non-blank 'identifiedSpace' in service metadata");
    isnt($json_object->{'schemaSpace'}, "",
        "Checking for non-blank 'schemaSpace' in service metadata");
};

# TODO: Test 'callback' for JSONP output.
