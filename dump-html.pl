#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_raw_titles );

my $imdb_id = shift or die "Must supply IMDb ID\n";
my $field = shift || 'content';

my $titles = get_raw_titles();

(my $title) = $titles->find(
    { imdb_id => $imdb_id, $field => { '$exists' => 1 } },
    { $field => 1 },
)->all;

use open ':std', ':encoding(UTF-8)';
print $title->{$field};
