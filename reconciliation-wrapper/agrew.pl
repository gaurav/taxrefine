#!/usr/bin/perl -w

=head1 NAME

agrew.pl -- Api.Gbif.org REconciliation Wrapper

=cut

use v5.010;

use strict;
use warnings;

# Version
our $VERSION = '0.1-dev1';

# Set up a UserAgent to call GBIF's API on.
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;

# Dancer and settings.
use Dancer;

set show_errors => 1;
set logger => 'console';

# Do nothing here.
get '/' => sub {
    redirect('/reconcile');
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
        'name' => "agrew.pl (Api.Gbif.org REconciliation Wrapper)/$VERSION",
        'identifierSpace' => 'http://ecat-dev.gbif.org/usage/',
        'view' => {
            'url' => 'http://ecat-dev.gbif.org/usage/{{id}}#contentLeft'
        },
        'preview' => {
            'url' => 'http://ecat-dev.gbif.org/usage/{{id}}#contentLeft',
            'width' => 430,
            'height' => 300
        },
        'schemaSpace' => 'http://rs.tdwg.org/dwc/terms/',
            # Since we mostly use DwC terms.
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

    say STDERR "process_query!";

    my @results;

    # Right now, we only use 'query'. Look up https://github.com/OpenRefine/OpenRefine/wiki/Reconciliation-Service-API#single-query-mode for other options.
    # Ideas:
    #   - use 'Family' for high-level filtering.
    my $name = $query{'query'};
    my $name_in_url = $name;

    # TODO: Better URLification.
    $name_in_url =~ s/ /%20/g;

    # In case of errors, try 10 times.
    my $request_time_start = time;

    my $response;
    for(my $x = 0; $x < 10; $x++) {
        my $url = 'http://api.gbif.org/name_usage/' . $name_in_url;
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
            my %unique_matches;

            my $time_taken = (time - $request_time_start);
            say STDERR (scalar @$gbif_match) . " matches found on GBIF for '$name' in $time_taken.";
            
            foreach my $match (@$gbif_match) {
                my $name = $match->{'canonicalName'} // $match->{'scientificName'};
                my $authority = $match->{'authorship'} // 'unknown';
                my $kingdom = $match->{'kingdom'} // 'Life';

                $unique_matches{$name}{$authority}{$kingdom} = []
                    unless exists $unique_matches{$name}{$authority}{$kingdom};

                push @{$unique_matches{$name}{$authority}{$kingdom}}, $match;
            }

            foreach my $name (sort keys %unique_matches) {
                foreach my $authority (sort keys %{$unique_matches{$name}}) {
                    foreach my $kingdom (sort keys %{$unique_matches{$name}{$authority}}) {
                        my @matches = @{$unique_matches{$name}{$authority}{$kingdom}};

                        # How do we summarize matches? EASY.
                        my $gbif_key;

                        my %summary;
                        foreach my $match (@matches) {
                            foreach my $field (keys %$match) {
                                $summary{$field}{$match->{$field}} = 0
                                    unless exists $summary{$field}{$match->{$field}};
                                $summary{$field}{$match->{$field}}++;

                                unless(defined $gbif_key) {
                                    if($field eq 'key') {
                                        $gbif_key = $match->{$field};
                                    }
                                }
                            }
                        }
                        
                        # Further simplify fields common for ALL checklists.
                        my $match_count = scalar @matches;
                        foreach my $field (keys %summary) {
                            foreach my $value (keys %{$summary{$field}}) {
                                my $count = $summary{$field}{$value};

                                if($count == $match_count) {
                                    $summary{$field} = $value;
                                }
                            }
                        }

                        my %result;

                        $result{'id'} = $gbif_key;
                        $result{'name'} = "$name $authority ($kingdom)";
                        $result{'type'} = ['http://ecat-dev.gbif.org/usage/'];
                        $result{'score'} = scalar @matches;
                        $result{'match'} = $JSON::false;
                        $result{'summary'} = \%summary;
                        $result{'full_gbif'} = $content;

                        push @results, \%result;
                    }
                }
            }
        }
    }

    my @sorted_results = sort { $b->{'score'} <=> $a->{'score'} } @results;

    # Add a dummy result so we know that all results are getting through.
    push @sorted_results, {
        id =>       "0",
        name =>     "(entries end here)",
        type =>     ['http://localhost:3333/taxref/result'],
        score =>    0,
        match =>    $JSON::false
    };

    return { 'result' => \@sorted_results };
}

start;
