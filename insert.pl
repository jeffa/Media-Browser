#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use MongoDB;
use File::Slurp;
use File::Basename;
use WWW::Mechanize;

use lib 'lib';
use MovieUtil qw( canonicalize );

my $client = MongoDB->connect( 'mongodb://localhost' );
my $db     = $client->get_database( 'movies' );
my $titles = $db->get_collection( 'raw_titles' );

my $url  = 'http://www.imdb.com/find?ref_=nv_sr_fn&s=tt&q=';
my $mech = WWW::Mechanize->new;

while (my $filename = <STDIN>) {
    chomp( $filename );
    my $term = canonicalize( $filename );
    print "\n$filename - ";
    if ($titles->find({ filename => $filename })->all) {
        print "SKIP";
        next;
    } else {
        print "INSERT";
        $mech->get( $url . $term );
        $titles->insert_one({
            filename    => $filename,
            term        => canonicalize( $filename ),
            search      => $mech->content,
        });
        sleep int rand(4);
    }
}


__DATA__
find /Volumes/TV  -type f \( -iname \*.divx -o -iname \*.m4v -o -iname \*.avi -o -iname \*.mkv -o -iname \*.mp4   \) -print
