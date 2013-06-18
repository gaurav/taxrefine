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
set logger => 'console';

# Do nothing here.
get '/' => sub {
    return 'boo!';
};

# Switch.
any '/reconcile' => sub {
    my $response = Dancer::SharedData->response;
    my $callback = param('callback');
    my $queries = param('queries');
    my $query = param('query');

    # There's a lot of cool data in the query, but for now let's just ignore that.
    my $result;
    if(defined $query) {
        $result = process_queries({'q' => $query});
    } elsif(defined $queries) {
        $result = process_queries(from_json($queries));
    } else {
        $result = get_service_metadata();
    }

    if(defined $callback) {
        $response->content_type('application/javascript');
        return "$callback(" . to_json($result) . ");";
    } else {
        $response->content_type('application/json');
        return to_json($result);
    }
};

# Return the service metadata.
sub get_service_metadata {
    return {
        'name' => 'agrew.pl (Api.Gbif.org REconciliation Wrapper)',
        'identifierSpace' => 'http://portal.gbif.org/ws/response/gbif', # Copied from Rod Page's code at https://github.com/rdmpage/phyloinformatics/blob/master/services/reconciliation_gbif.php#L16, not sure what it does.
        'schemaSpace' => 'http://rdf.freebase.com/ns/type.object.id',
    };
}

start;
