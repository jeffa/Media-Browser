#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles get_details );

$| = 1;
use open ':std', ':encoding(UTF-8)';

my $titles = get_raw_titles();

my $attr = $ARGV[0] ? { imdb_id => shift() } : { meta => { '$exists' => 0 } };

my $iter = $titles->find( $attr );
while (my $movie = $iter->next) {
    print $movie->{filename}, ': ';
    if ($movie->{imdb_id} !~ /^tt\d{7}$/) {
        print "SKIPPED!\n";
        next;
    }
    my $meta = get_details( $movie );
    $titles->update_many( { _id => $movie->{_id} }, { '$set' => {meta => $meta} } );
    print $meta->{title}, $/;
}
