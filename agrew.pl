#!/usr/bin/perl -w

=head1 NAME

agrew.pl -- Api.Gbif.org REconciliation Wrapper

=cut

use v5.010;

use strict;
use warnings;

# Dancer and settings.
use Dancer;

set show_errors => 1;

# Do nothing here.
get '/' => sub {
    return 'boo!';
};

# Switch.
get '/reconcile' => sub {
    my $response = Dancer::SharedData->response;
    my $callback = param('callback');
    my $queries = param('queries');
    my $query = param('query');

    # There's a lot of cool data in the query, but for now let's just ignore that.

    my $result = {'error' => "No result defined."};
    
    if(defined $callback) {
        $response->content_type('application/javascript');
        return "$callback(" . to_json($result) . ");";
    } else {
        $response->content_type('application/json');
        return to_json($result);
    }
};

start;
