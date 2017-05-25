#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles );

my $titles = get_raw_titles();

my $attr = $ARGV[0]
    ? { imdb_id => shift() }
    : { content => { '$exists' => 1 }, fullcredits => { '$exists' => 1 }}
;

my $iter = $titles->find( $attr, { search => 0, content => 0, fullcredits => 0 } );

while (my $movie = $iter->next) {
    print Dumper $movie->{meta};
}

print $titles->count(), " titles found\n";;


# tt0066473 <-- test for unicode (3rd writer)
# tt1436045 <-- test for unicode title
