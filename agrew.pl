#!/usr/bin/perl -w

=head1 NAME

agrew.pl -- Api.Gbif.org REconciliation Wrapper

=cut

use v5.010;

use strict;
use warnings;

# Set up a UserAgent to call GBIF's API on.
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;

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
        # This is deprecated anyway, but just in case ...
        if($query =~ /^\s*{/) {
            # A JSON query
            $result = process_queries({'q' => from_json($query)})->{'q'};
        } else {
            # A plain string query
            $result = process_queries({'q' => { 'query' => $query }})->{'q'};
        }
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

# Process a number of queries.
# TODO: make this async to make it slightly faster maybe.
sub process_queries {
    my $queries_ref = shift;
    my %queries = %$queries_ref;
    my %results;

    foreach my $query (keys %queries) {
        $results{$query} = process_query($queries{$query});
    }

    return \%results;
}

sub process_query {
    my $query_ref = shift;
    my %query = %$query_ref;

    my @results;

    # Right now, we only use 'query'. Look up https://github.com/OpenRefine/OpenRefine/wiki/Reconciliation-Service-API#single-query-mode for other options.
    my $name = $query{'query'};

    # TODO: Better URLification.
    $name =~ s/ /%20/g;

    # In case of errors, try 10 times.
    my $response;
    for(my $x = 0; $x < 10; $x++) {
        my $url = 'http://api.gbif.org/name_usage/' . $name;
        $response = $ua->get($url);

        if($response->is_success) {
            last;
        } else {
            warn "Could not connect to '$url': " . $response->status_line . "; retrying.";
        }

        sleep(2);
    }

    if($response->is_success) {
        my $content = $response->decoded_content;
        my $gbif_match = from_json($content);

        if(0 == scalar @$gbif_match) {
            # No matches.
        } else {
            # TODO: At this point, summarize down to one match per name. But we'll do that latter.
            foreach my $match (@$gbif_match) {
                my %result;

                $result{'id'} = $content;   # hee hee
                $result{'name'} = $match->{'scientificName'};
                $result{'type'} = ['http://localhost:3333/taxref/result'];
                $result{'score'} = 0.5;
                $result{'match'} = $JSON::false;

                push @results, \%result;
            }
        }
    }

    return { 'result' => \@results };
}

start;