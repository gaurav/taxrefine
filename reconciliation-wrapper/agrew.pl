#!/usr/bin/perl -w

=head1 NAME

agrew.pl -- Api.Gbif.org REconciliation Wrapper

=cut

use v5.010;

use strict;
use warnings;

use Data::Dumper;
use URI::Escape;
use Time::HiRes qw/time/;

# Version and settings.
our $VERSION = '0.1-dev7';

our $WEB_ROOT = '/gbifchecklists';

our $FLAG_DISPLAY_ENTRIES_END_HERE = 0;

# Set up a UserAgent to call GBIF's API on.
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;

# Dancer and settings.
use Dancer;

set show_errors => 1;
set logger => 'console';

# Do nothing here.
get "$WEB_ROOT/" => sub {
    redirect("$WEB_ROOT/reconcile");
};

# Point at the code from here.
get "$WEB_ROOT/code" => sub {
    redirect("https://github.com/gaurav/taxrefine/tree/master/reconciliation-wrapper");
};

# Switch.
any "$WEB_ROOT/reconcile" => sub {
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

    my $json_string = to_json($result, {utf8 => 1});

    if(defined $callback) {
        $response->content_type('application/javascript');
        return "$callback(" . $json_string . ");";
    } else {
        $response->content_type('application/json');
        return $json_string;
    }
};

# Return the service metadata.
sub get_service_metadata {
    return {
        'name' => "agrew.pl (Api.Gbif.org REconciliation Wrapper)/$VERSION",
        'identifierSpace' => 'http://uat.gbif.org/species/',
        'view' => {
            'url' => 'http://uat.gbif.org/species/{{id}}#overview'
        },
        'preview' => {
            'url' => 'http://uat.gbif.org/species/{{id}}#overview',
            'width' => 700,
            'height' => 350 
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

    # Right now, we only use 'query'. Look up https://github.com/OpenRefine/OpenRefine/wiki/Reconciliation-Service-API#single-query-mode for other options.
    # Ideas:
    #   - use 'Family' for high-level filtering.
    my $name = $query{'query'};
    say STDERR "Query: '$name'";

    my $request_time_start = time;
    my @results = get_gbif_name_usages_for_name($name);
    my $time_taken = (time - $request_time_start);
    printf STDERR "  Retrieved %d matches for '$name' in %.4f ms.\n", (scalar @results), $time_taken*1000;

    if((scalar @results) == 0) { 
        say STDERR "  No matches found, carrying out full-text search instead.";

        @results = get_gbif_full_text_matches_for_name($name);

        $time_taken = (time - $request_time_start);
        printf STDERR "  Retrieved %d matches for '$name' in %.4f ms.\n", (scalar @results), $time_taken*1000;
    }

    my @summarized = summarize_name_usages(@results);
    $time_taken = (time - $request_time_start);
    printf STDERR "  Summarized '$name' to %d matches in %.4f ms.\n", (scalar @summarized), $time_taken*1000;

    my @sorted_results = sort { $b->{'score'} <=> $a->{'score'} } @summarized;

    # Add a dummy result so we know that all results are getting through.
    if($FLAG_DISPLAY_ENTRIES_END_HERE) {
        push @sorted_results, {
            id =>       "0",
            name =>     "(entries end here)",
            type =>     ['http://localhost:3333/taxref/result'],
            score =>    0,
            match =>    $JSON::false
        };
    }

    # TODO: rewrite this so we can send back error messages (even if OpenRefine can't do anything sensible with them).

    return { 'result' => \@sorted_results };
}

our $LIMIT_URL_RETRIES = 10;    # How often should this code try a URL (GET) request?
our $SLEEP_BETWEEN_URL_RETRIES = 2; # How long should this code sleep between URL retries?

sub retry_url_until_success($) {
    my $url = shift;
    my $response;

    for(my $x = 0; $x < $LIMIT_URL_RETRIES; $x++) {
        $response = $ua->get($url);

        if($response->is_success) {
            return $response;
        } else {
            warn "Could not connect to '$url': " . $response->status_line . "; retrying.";
        }
    
        sleep($SLEEP_BETWEEN_URL_RETRIES);
    }

    warn "Giving up connecting to URL '$url': " . Dumper($response) . " (end of dumper output).";
    return $response;
}

sub get_gbif_name_usages_for_name {
    my $name = shift;
    my $name_in_url = uri_escape($name);    # URLification.

    my $response = retry_url_until_success("http://api.gbif.org/lookup/name_usage?strict=true&verbose=true&name=$name_in_url");
    return unless ($response->is_success);
        
    my $content = $response->decoded_content;

    # Four options here: we might have an invalid response, or a valid response which has:
    #   'matchType' of 'NONE': no matches
    #   'matchType' of 'FUZZY': under the current implementation, let's ignore this.
    #   'matchType' of 'EXACT': perfect.
    my $gbif_nub_match = from_json($content);   # This will croak on error, i.e. if given invalid input.

    my @gbif_nub_usage_ids;

    # TODO: We're trusting in api.gbif.org to tell us when matches are not
    sub addMatch {
        my $usage_ids = shift;
        my $match = shift;

        given($match->{'matchType'}) {
            when('NONE') {
                # No matches ... but maybe there are alternatives?
                my $alternatives = $match->{'alternatives'};
                if($alternatives) {
                    foreach my $alternative (@$alternatives) {
                        addMatch($usage_ids, $alternative);
                    }
                }

                return;
            }

            when('FUZZY') {
                # Ignore fuzzy matches for now. We'll deal with them eventually.
                return;
            }

            when('EXACT') {
                push @$usage_ids, $match->{'usageKey'};
                return;
            }
        }
    }

    addMatch(\@gbif_nub_usage_ids, $gbif_nub_match);

    my @gbif_related;

    foreach my $nub_key (@gbif_nub_usage_ids) {
        unless($nub_key =~ /^\d+$/) {
            warn "ERROR: Invalid usageKey: got $nub_key, expected numeric; skipping request";
            return;
        }

        # Find all related name usages to the taxon.
        $response = retry_url_until_success("http://api.gbif.org/name_usage/$nub_key/related");
        return unless ($response->is_success);

        $content = $response->decoded_content;
        my $gbif_related = from_json($content);

        foreach my $related (@$gbif_related) {
            $related->{'relatedToUsageKey'} = $nub_key;
            push @gbif_related, $related;
        }

    }

    return @gbif_related;
}

sub get_gbif_full_text_matches_for_name {
    my $name = shift;

    my @matches;

    sub gbif_ft_search($$$) {
        my $name = shift;
        my $name_in_url = uri_escape($name);    # URLification.

        my $offset = shift;
        my $limit = shift;

        my $response = retry_url_until_success("http://api.gbif.org/name_usage/search?q=$name_in_url&offset=$offset&limit=$limit");
        return () unless ($response->is_success);
        
        my $content = $response->decoded_content;
        return from_json($content);   # This will croak on error, i.e. if given invalid input.
    }

    # Limit total to 200 records.
    my $response = gbif_ft_search($name, 0, 200);
    my $total = $response->{'count'};
    foreach my $result (@{$response->{'results'}}) {
        push @matches, $result if 
            (exists $result->{'scientificName'} && $result->{'scientificName'} eq $name) 
            || (exists $result->{'canonicalName'} && $result->{'canonicalName'} eq $name);
    }

    # say STDERR "(DEBUG) In full-text search: expected $total, actually retrieved " . (scalar @matches) . " matches.";

    foreach my $match (@matches) {
        # Rename 'key' to 'usageKey' for consistency with /lookup/name_usage
        $match->{'usageKey'} = $match->{'key'};

        # We need a 'relatedToUsageKey' to search on. Unfortunately, 
        # actually figuring out the best GBIF Nub match would take
        # a fairly long time.
        $match->{'relatedToUsageKey'} = $match->{'key'};
    }

    return @matches;
}

sub summarize_name_usages {
    my @name_usages = @_;

    # Summarize results.
    my %unique_matches;
    my @summarized;

    foreach my $match (@name_usages) {
        my $name = $match->{'canonicalName'} // $match->{'scientificName'};
        my $accepted_name = $match->{'acceptedNameUsage'} // $match->{'accepted'} // ''; 
        my $authority = $match->{'authorship'} // 'unknown';
        my $kingdom = $match->{'kingdom'} // 'Life';

        $unique_matches{$name}{$accepted_name}{$authority}{$kingdom} = []
            unless exists $unique_matches{$name}{$accepted_name}{$authority}{$kingdom};

        push @{$unique_matches{$name}{$accepted_name}{$authority}{$kingdom}}, $match;
    }

    foreach my $name (sort keys %unique_matches) {
        foreach my $accepted_name (sort keys %{$unique_matches{$name}}) {
            foreach my $authority (sort keys %{$unique_matches{$name}{$accepted_name}}) {
                foreach my $kingdom (sort keys %{$unique_matches{$name}{$accepted_name}{$authority}}) {
                    my @matches = @{$unique_matches{$name}{$accepted_name}{$authority}{$kingdom}};

                    # How do we summarize matches? EASY.

                    # This is the GBIF Nub identifier we called: this way,
                    # the 'id' will (almost) always be on GBIF Nub.
                    my $gbif_key; 

                    my %summary;
                    foreach my $match (@matches) {
                        $gbif_key = $match->{'relatedToUsageKey'}
                            unless defined $gbif_key;

                        foreach my $field (keys %$match) {
                            my $value = $match->{$field};

                            $value = Dumper($value)
                                unless ref($value) eq '';

                            $summary{$field}{$value} = 0
                                unless exists $summary{$field}{$value};
                            $summary{$field}{$value}++;
                        }
                    }

                    die "No gbif_key provided!" unless defined $gbif_key;
                    
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
                    $result{'name'} = $name;
                    $result{'name'} .=  " $authority" if ($authority ne '');
                    $result{'name'} .= " [=> $accepted_name]" unless $accepted_name eq '';
                    $result{'name'} .= " ($kingdom)";
                    $result{'type'} = ['http://uat.gbif.org/species/'];
                    $result{'score'} = scalar @matches;
                    $result{'match'} = $JSON::false;
                    $result{'summary'} = \%summary;
                    # $result{'full_gbif'} = $content;

                    push @summarized, \%result;
                }
            }
        }
    }

    return @summarized;
}

start;
