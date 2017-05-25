#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles );

my $titles = get_raw_titles();
my $iter = $titles
    ->find( {}, {imdb_id => 1, filename => 1} )
    ->sort( {filename=>1} )
;

while (my $movie = $iter->next) {
    print join( '|', $movie->{imdb_id}, $movie->{filename} ), $/;
}
