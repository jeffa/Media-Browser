#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles );

my $titles = get_raw_titles();

my %largest;
my $iter = $titles->find();
while (my $movie = $iter->next) {

    my $length = length( $movie->{filename} );
    $largest{filename} = $length if $length > $largest{filename};

    for my $key (qw(title tagline story mpaa ratio cover)) {
        my $length = length( $movie->{meta}{$key} || '' );
        $largest{$key} = $length if $length > $largest{$key};
    }

    for my $key (qw(writers directors)) {
        for (@{ $movie->{meta}{$key} }) {
            my $length = length( $_->{name} );
            $largest{$key} = $length if $length > $largest{$key};
        }
    }

    for my $key (qw(genres country duration)) {
        for (@{ $movie->{meta}{$key} }) {
            my $length = length( $_ );
            $largest{$key} = $length if $length > $largest{$key};
        }
    }
}

print Dumper \%largest;
