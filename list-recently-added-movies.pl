#!/usr/bin/env perl
use strict;
use warnings;
use File::Find::Rule;

my $limit = shift || 19;
$limit = 19 unless int($limit);

my @files = File::Find::Rule->file()->name( '*.avi', '*.mp4', '*.mkv', '*.divx', '*.m4v' )->in( '/Volumes/MOVIES' );
my @sorted = sort { -M $a <=> -M $b } @files;
print "$_\n" for @sorted[ 0 .. $limit ];

