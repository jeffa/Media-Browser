#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles get_details );

my $titles = get_raw_titles();

my $attr = $ARGV[0]
    ? { imdb_id => shift() }
    : { content => { '$exists' => 1 }, fullcredits => { '$exists' => 1 }}
;

my $iter = $titles->find( $attr, { search => 0 } );

while (my $movie = $iter->next) {
    my $meta = get_details( $movie );
    print Dumper $meta;
}
