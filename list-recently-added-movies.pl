#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;

use File::Find::Rule;

GetOptions (
    'dir=s'     => \my $dir,
    'limit=i'   => \my $limit,
    'help'      => \my $help,
    'man'       => \my $man,
);

pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;
pod2usage( 'dir must be valid path' ) unless $dir && -d $dir;
$limit = 20 unless int($limit);

my @sorted = sort { -M $a <=> -M $b } File::Find::Rule
    ->file()
    ->name( '*.avi', '*.mp4', '*.mkv', '*.divx', '*.m4v' )
    ->in( $dir )
;

print "$_\n" for @sorted[ 0 .. $limit - 1 ];

__END__
=head1 NAME

list-recently-added-movies - fetch IMDb page(s)

=head1 SYNOPSIS

./list-recently-added-movies --dir=/Volumes/MOVIES --limit=50

 Options:
   --dir        path to find movies from 
   --limit      limit number displayed
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--dest>

Destination (path) to move files to. Trailing slash will be added if not provided.

  --dest=/Volumes/TV/DOCUMENTARIES

=back
