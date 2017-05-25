#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use MongoDB;
use lib 'lib';
use MovieUtil qw( extract_imdb );

my $client = MongoDB->connect( 'mongodb://localhost' );
my $db     = $client->get_database( 'movies' );
my $titles = $db->get_collection( 'raw_titles' );

my $iter = $titles->find({ imdb_id => 'SKIP'}, { search => 0 })->sort({ term => 1 });

my $imdb_id;
while (my $movie = $iter->next) {

    print $movie->{filename}, ': '; chomp($imdb_id = <STDIN>);
    unless ($imdb_id eq 'DEAD') {
        $imdb_id = extract_imdb( $imdb_id );
        die "bad $imdb_id\n" unless $imdb_id =~ /^tt\d{7}$/;
    }

    $db->get_collection( 'raw_titles' )->update_many(
        { _id => $movie->{_id} },
        { '$set' => {imdb_id => $imdb_id} }
    );

    printf "Update %s => %s\n\n", $movie->{_id}, $imdb_id;
}
