#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use MongoDB;
use WWW::Mechanize;

my $client = MongoDB->connect( 'mongodb://localhost' );
my $db     = $client->get_database( 'movies' );
my $titles = $db->get_collection( 'raw_titles' );

my @skipped = $titles->find({ imdb_id => 'SKIP'}, { search => 0 })->sort({ filename => 1 })->all;

unless (@skipped) {
    print "Nothing to be skipped. :)\n";
    exit;
}

open my $fh, '>', 'SKIPPED.txt' or die "Can't write: $!\n";

for my $movie (@skipped) {
    print $fh $movie->{filename}, $/;
    $titles->delete_many( { _id => $movie->{_id} } );
}

close $fh;
