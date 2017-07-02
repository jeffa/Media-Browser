#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;

use MongoDB;
use WWW::Mechanize;
use Encode qw( decode encode );

GetOptions (
    'page=s'    => \my $page,
    'title=s'   => \my $title,
    'help'      => \my $help,
    'man'       => \my $man,
);
pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;

my %valid_pages = (
    main    => '',
    credits => 'fullcredits',
    release => 'releaseinfo',
);
my @to_fetch = values %valid_pages;

if ($page) {
    die "Invalid page: $page\n" unless exists $valid_pages{$page};
    @to_fetch = $valid_pages{$page};
}
if ($title) {
    die "Invalid title: $title\n" unless $title =~ /^tt\d{7}$/;
}

my $mech = WWW::Mechanize->new;
my $URL  = 'http://www.imdb.com/title/%s/%s';

my $client = MongoDB->connect( 'mongodb://localhost' );
my $db     = $client->get_database( 'movies' );
my $titles = $db->get_collection( 'raw_titles' );
my $search = $title ? { imdb_id => $title } : { meta => { '$exists' => 0 } };
my @movies = $titles->find( $search )->all;
for my $movie (@movies) {

    print $movie->{filename}, ":\n";
    for my $page (@to_fetch) {
        if ($movie->{imdb_id} =~ /(?:SKIP|DEAD)/ or !$movie->{imdb_id}) {
            print "skipping $movie->{filename}\n";
            next;
        }
        my $url = sprintf( $URL, $movie->{imdb_id}, $page );
        $mech->get( $url );
        $titles->update_many(
            { _id    => $movie->{_id} },
            { '$set' => { ($page || 'content') => $mech->content } },
        );
        print "\t$url\n";
        sleep int rand(4);
    }
}

__END__
=head1 NAME

fetch-details - fetch IMDb page(s)

=head1 SYNOPSIS

fetch-details --page=main --title=tt1234567

 Options:
   --page       which page to fetch
   --title      which title to fetch
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--page>

Page to fetch: main, credits or release. Specify none to grab all pages.

=item B<--title>

Title to fetch. Specify none to grab all titles.

=back
