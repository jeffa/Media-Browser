#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );

my $dbh = get_dbh();

my $id = shift;
die "Must supply title or IMDb ID\n" unless $id;
my $field = $id =~ /^tt\d{7}$/ ? 'imdb_id' : 'title_id';

my $sth = $dbh->selectall_arrayref( 
    "select * from titles where $field = ?",
    {Slice => {}},
    $id,
);

print Dumper $sth;
